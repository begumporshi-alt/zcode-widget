import SwiftUI
import Foundation
import UserNotifications
import GRDB

/// macOS heat monitor for the ZCode widget.
///
/// Raw °C sensors need an admin password on Apple Silicon (AppleSMC is not
/// readable by non-root processes on macOS 15), so heat is detected the way the
/// OS itself reports it:
/// - `ProcessInfo.thermalState` (nominal → fair → serious → critical), polled
///   every 8 s, and
/// - live per-process CPU% (sampled via `top`, two passes 1 s apart), so a heat
///   event can name the actual culprit — usually `zcode-cli`/`ZCode` running a
///   chat — and attribute it to the chat session that was active in the
///   token-tail log at that moment.
///
/// A heat event is recorded (and, if enabled, a banner posted) when thermal
/// pressure reaches serious/critical, or when the machine sustains fair
/// pressure under heavy CPU load. Banners are throttled by a 10-minute cooldown
/// so a long hot spell does not spam.
@MainActor
final class ThermalMonitor: ObservableObject {
    static let shared = ThermalMonitor()

    static let categoryID = "THERMAL_ALERT"
    private static let alertsEnabledKey = "thermalAlertsEnabled"
    private static let historyPath = NSHomeDirectory() + "/.zcode/widget-thermal.json"
    private static let historyLimit = 50
    /// Minimum gap between banners (and between recorded events) so a long hot
    /// spell surfaces once, then only if it persists.
    private static let cooldown: TimeInterval = 600
    /// Records from token-tail.jsonl count as "this chat is active" only when
    /// inside this window around the heat moment.
    private static let chatWindow: TimeInterval = 600
    private static let tailBytes: UInt64 = 262_144
    private static let tickInterval: TimeInterval = 8
    /// CPU sampling cadence: every tick while hot, every other tick otherwise.
    private static let cpuEveryTicks = 2

    // MARK: Published state

    @Published private(set) var pressure: ProcessInfo.ThermalState = .nominal
    @Published private(set) var processes: [ProcessLoad] = []
    @Published private(set) var events: [HeatEvent] = []
    /// True while the machine is in a serious/critical thermal state.
    @Published private(set) var isHot = false
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var alertsEnabled: Bool

    /// Invoked when the user clicks a thermal banner — opens the Thermal tab.
    var onOpenThermal: (() -> Void)?

    /// Newest recorded heat event (UI helpers + "ongoing" hint).
    var latestEvent: HeatEvent? { events.last }

    // MARK: Internal state

    private var timer: Timer?
    private var started = false
    private var tickCount = 0
    private var cpuSampleInFlight = false
    private var warmTicks = 0
    private var lastBannerAt = Date.distantPast
    private var lastEventAt = Date.distantPast
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private init() {
        alertsEnabled = UserDefaults.standard.object(forKey: Self.alertsEnabledKey) as? Bool ?? true
    }

    // MARK: Model

    struct ProcessLoad: Codable, Equatable, Identifiable {
        var pid: Int
        var cpu: Double
        var name: String
        var isZCodeRelated: Bool
        var id: Int { pid }
    }

    struct ChatActivity: Codable, Equatable, Identifiable {
        var sessionID: String
        var label: String
        var project: String
        var model: String
        var requests: Int
        var lastActivityMs: Int64
        var directory: String?
        var id: String { sessionID }
        var lastActivity: Date { Date(timeIntervalSince1970: Double(lastActivityMs) / 1000) }
    }

    struct HeatEvent: Codable, Equatable, Identifiable {
        var id = UUID()
        var atMs: Int64
        /// Peak `ProcessInfo.ThermalState.rawValue` during the episode.
        var level: Int
        var peakCPU: Double
        var processes: [ProcessLoad]
        var chats: [ChatActivity]
        /// Directory of the most active chat — lets the cool-down helper open
        /// the project the hot chat was working in.
        var chatDirectory: String?

        var at: Date { Date(timeIntervalSince1970: Double(atMs) / 1000) }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        loadHistory()

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func setAlertsEnabled(_ on: Bool) {
        alertsEnabled = on
        UserDefaults.standard.set(on, forKey: Self.alertsEnabledKey)
    }

    func clearHistory() {
        events = []
        try? FileManager.default.removeItem(atPath: Self.historyPath)
    }

    // MARK: Sampling

    private func tick() {
        tickCount += 1
        let level = ProcessInfo.processInfo.thermalState
        pressure = level
        lastSampleAt = Date()
        isHot = level == .serious || level == .critical

        if level == .fair { warmTicks += 1 } else { warmTicks = 0 }

        let wantCPU = isHot || processes.isEmpty || tickCount % Self.cpuEveryTicks == 0
        if wantCPU {
            Task { await sampleProcesses() }
        }
    }

    /// Runs `top -l 2` (two passes 1 s apart → real current CPU%) and publishes
    /// the top consumers, then assesses whether this is a heat event.
    private func sampleProcesses() async {
        guard !cpuSampleInFlight else { return }
        cpuSampleInFlight = true
        defer { cpuSampleInFlight = false }

        let output = await runTop()
        let top = Array(Self.parseTop(output).prefix(8))
        processes = top

        await assess(now: Date(), processes: top)
    }

    private nonisolated func runTop() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
                process.arguments = ["-l", "2", "-s", "1", "-n", "20", "-o", "cpu", "-stats", "pid,cpu,command"]
                var environment = ProcessInfo.processInfo.environment
                environment["COLUMNS"] = "300"
                process.environment = environment
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Parses the second (delta) sample of `top` output into ProcessLoad rows.
    private nonisolated static func parseTop(_ output: String?) -> [ProcessLoad] {
        guard let output else { return [] }
        let lines = output.components(separatedBy: "\n")
        // Take everything after the LAST "Processes:" header — that is the
        // second sample, which carries the true current CPU%.
        guard let lastHeader = lines.lastIndex(where: { $0.hasPrefix("Processes:") }) else { return [] }

        guard let rowPattern = try? NSRegularExpression(pattern: #"^\s*(\d+)\s+(\d+(?:\.\d+)?)\s+(.+)$"#) else { return [] }
        var result: [ProcessLoad] = []
        for line in lines[(lastHeader + 1)...] {
            guard let match = rowPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let pidRange = Range(match.range(at: 1), in: line),
                  let cpuRange = Range(match.range(at: 2), in: line),
                  let nameRange = Range(match.range(at: 3), in: line),
                  let pid = Int(line[pidRange]),
                  let cpu = Double(line[cpuRange])
            else { continue }
            var name = String(line[nameRange])
            if name.hasPrefix("/") {
                name = (name as NSString).lastPathComponent
            }
            name = String(name.prefix(60))
            let lower = name.lowercased()
            let isZCode = lower.contains("zcode") || lower.contains("claude")
            result.append(ProcessLoad(pid: pid, cpu: cpu, name: name, isZCodeRelated: isZCode))
            if result.count >= 12 { break }
        }
        return result
    }

    // MARK: Heat assessment

    /// Called after every CPU sample: records a heat event (and banners when
    /// enabled) if the machine is seriously hot or sustain-warm under load.
    private func assess(now: Date, processes: [ProcessLoad]) {
        let level = ProcessInfo.processInfo.thermalState
        let totalCPU = processes.prefix(6).reduce(0) { $0 + $1.cpu }

        // Serious/critical pressure, or "fair" sustained over ≥ 3 warm ticks
        // (~24 s) with a heavily loaded CPU.
        let hot = level == .serious || level == .critical
        let warmUnderLoad = level == .fair && warmTicks >= 3 && totalCPU >= 150
        guard hot || warmUnderLoad else { return }

        guard now.timeIntervalSince(lastEventAt) >= Self.cooldown else { return }
        lastEventAt = now

        Task {
            let chats = await activeChats(within: Self.chatWindow, at: now)
            var event = HeatEvent(atMs: Int64(now.timeIntervalSince1970 * 1000),
                                  level: level.rawValue,
                                  peakCPU: totalCPU,
                                  processes: processes,
                                  chats: chats)
            event.chatDirectory = chats.first?.directory

            events.append(event)
            if events.count > Self.historyLimit {
                events.removeFirst(events.count - Self.historyLimit)
            }
            persist()

            if alertsEnabled
                && (hot || totalCPU >= 250)
                && now.timeIntervalSince(lastBannerAt) >= Self.cooldown {
                lastBannerAt = now
                postBanner(for: event)
            }
        }
    }

    /// Latest activity per session in the token tail within the window, joined
    /// with titles/projects/directories from the session table (read-only).
    private func activeChats(within window: TimeInterval, at now: Date) async -> [ChatActivity] {
        guard let tail = await readTail(), !tail.isEmpty else { return [] }

        let cutoffMs = Int64(now.timeIntervalSince1970 * 1000) - Int64(window * 1000)
        var perSession: [String: (lastMs: Int64, model: String, requests: Int)] = [:]

        for line in tail.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = obj["session_id"] as? String,
                  let startedMs = (obj["started_at"] as? NSNumber)?.int64Value
            else { continue }
            guard startedMs >= cutoffMs else { continue }
            var entry = perSession[sessionID] ?? (startedMs, "", 0)
            entry.lastMs = max(entry.lastMs, startedMs)
            if entry.model.isEmpty, let model = obj["model_id"] as? String {
                entry.model = model
            }
            entry.requests += 1
            perSession[sessionID] = entry
        }
        guard !perSession.isEmpty else { return [] }

        // Bound the IN clause to the sessions with the most recent activity.
        let ids = perSession.sorted { $0.value.lastMs > $1.value.lastMs }.prefix(30).map { $0.key }
        let meta = Self.sessionMeta(for: ids)

        return perSession
            .map { sessionID, entry in
                let m = meta[sessionID]
                let title = m?.title ?? ""
                let label: String
                if !title.isEmpty {
                    label = String(title.prefix(72))
                } else if let m, !m.project.isEmpty {
                    label = "chat in \(m.project)"
                } else {
                    label = String(sessionID.prefix(24))
                }
                return ChatActivity(sessionID: sessionID,
                                    label: label,
                                    project: m?.project ?? "",
                                    model: entry.model,
                                    requests: entry.requests,
                                    lastActivityMs: entry.lastMs,
                                    directory: m?.directory)
            }
            .sorted { $0.lastActivityMs > $1.lastActivityMs }
            .prefix(4)
            .map { $0 }
    }

    private nonisolated func readTail() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let path = NSHomeDirectory() + "/.zcode/log/token-tail.jsonl"
                guard let handle = FileHandle(forReadingAtPath: path) else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                let offset = size > Self.tailBytes ? size - Self.tailBytes : 0
                try? handle.seek(toOffset: offset)
                let data = handle.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    /// Titles/projects/directories for the given session IDs. Sync (called from
    /// a nonisolated helper so GRDB's sync `read` overload is used — inside an
    /// async function the async overload wins and would need `await`).
    private nonisolated static func sessionMeta(for ids: [String])
        -> [String: (title: String, project: String, directory: String?)] {
        guard !ids.isEmpty else { return [:] }
        var meta: [String: (title: String, project: String, directory: String?)] = [:]
        do {
            try Database.shared.queue.read { db in
                let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                let rows = try Row.fetchAll(db,
                                            sql: "SELECT id, title, project_id, directory FROM session WHERE id IN (\(placeholders))",
                                            arguments: StatementArguments(ids))
                for row in rows {
                    guard let id = row["id"] as? String else { continue }
                    meta[id] = ((row["title"] as? String) ?? "",
                                Self.projectShortName((row["project_id"] as? String) ?? ""),
                                row["directory"] as? String)
                }
            }
        } catch {
            // DB may be briefly locked by ZCode — attribution falls back to
            // session IDs only; the event is still recorded.
        }
        return meta
    }

    private nonisolated static func projectShortName(_ projectID: String) -> String {
        guard let last = projectID.split(separator: "-").last else { return projectID }
        return last.isEmpty ? projectID : String(last)
    }

    // MARK: Persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.historyPath)) else { return }
        if let decoded = try? Self.decoder.decode([HeatEvent].self, from: data) {
            events = Array(decoded.suffix(Self.historyLimit))
        }
    }

    private func persist() {
        guard let data = try? Self.encoder.encode(events) else { return }
        let url = URL(fileURLWithPath: Self.historyPath)
        let tmp = URL(fileURLWithPath: Self.historyPath + ".tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    // MARK: Notifications

    private func postBanner(for event: HeatEvent) {
        let level = ProcessInfo.ThermalState(rawValue: event.level) ?? .serious
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: level)
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["kind": "thermal"]

        var parts: [String] = []
        if let hot = event.processes.first(where: { $0.isZCodeRelated }) ?? event.processes.first {
            parts.append("\(hot.name) \(Int(hot.cpu))% CPU")
        }
        if let chat = event.chats.first {
            parts.append("'\(chat.label)' chat active")
        }
        if parts.isEmpty {
            parts.append("CPU \(Int(event.peakCPU))%")
        }
        content.body = parts.joined(separator: " · ")

        let center = UNUserNotificationCenter.current()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            center.add(UNNotificationRequest(identifier: "thermal-\(event.id)",
                                             content: content,
                                             trigger: nil))
        case .notDetermined:
            // Ask on first heat event so the request has context.
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        center.add(UNNotificationRequest(identifier: "thermal-\(event.id)",
                                                         content: content,
                                                         trigger: nil))
                    }
                }
            }
        default:
            break // Denied — the in-widget history still records the event.
        }
    }

    private static func title(for level: ProcessInfo.ThermalState) -> String {
        switch level {
        case .critical: return "Mac critically hot"
        case .serious: return "Mac is running hot"
        case .fair: return "Mac under heavy load"
        case .nominal: return "Mac thermal warning"
        @unknown default: return "Mac thermal warning"
        }
    }

    // MARK: Display helpers

    static func levelTitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    static func color(for state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .orange
        case .serious: return .red
        case .critical: return .red
        @unknown default: return .secondary
        }
    }

    static func levelWord(_ raw: Int) -> String {
        levelTitle(ProcessInfo.ThermalState(rawValue: raw) ?? .nominal)
    }
}
