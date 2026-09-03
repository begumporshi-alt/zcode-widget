import Foundation
import Combine

// MARK: - Priority

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case none = 0, low, medium, high

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

// MARK: - Task model

/// A single tracked task. `lastRemindedAt` stores the due date up to which a
/// reminder was *delivered or scheduled* — the reminder scanner uses it to
/// avoid double banners (the exact-time system notification fires at the due
/// date, so the scanner must not re-notify a task whose delivery was already
/// arranged) and to avoid re-notifying stale overdue tasks on every launch.
struct TaskItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var notes: String
    var dueDate: Date?
    var reminderEnabled: Bool
    var priority: TaskPriority
    var completed: Bool
    var createdAt: Date
    var completedAt: Date?
    var lastRemindedAt: Date?
    /// Bumped on every user save. Lets the scanner treat a task that was just
    /// saved with a past due date as intentional ("remind me now"), without
    /// spamming reminders for tasks that went overdue weeks ago.
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         title: String,
         notes: String = "",
         dueDate: Date? = nil,
         reminderEnabled: Bool = false,
         priority: TaskPriority = .none,
         completed: Bool = false) {
        let now = Date()
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.reminderEnabled = reminderEnabled && dueDate != nil
        self.priority = priority
        self.completed = completed
        self.createdAt = now
        self.completedAt = completed ? now : nil
        self.lastRemindedAt = nil
        self.updatedAt = now
    }
}

// MARK: - Store

/// Loads/saves ~/.zcode/widget-tasks.json (same user-visible convention as
/// widget-settings.json and prompts.json, so data survives reinstalls).
/// Single-writer: views and the reminder engine all go through the shared
/// instance, so nothing clobbers the file.
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    /// Default: user-visible. Overridable for tests.
    static var tasksPath = NSHomeDirectory() + "/.zcode/widget-tasks.json"

    @Published private(set) var tasks: [TaskItem] = []
    @Published var loadError: String?

    private var fileURL: URL { URL(fileURLWithPath: Self.tasksPath) }
    private var hasLoaded = false

    func load() {
        guard !hasLoaded else { return }
        reload()
    }

    /// Re-reads from disk even if already loaded (used by tests).
    func reload() {
        hasLoaded = true
        loadError = nil
        if FileManager.default.fileExists(atPath: Self.tasksPath) {
            do {
                let data = try Data(contentsOf: fileURL)
                tasks = try Self.decoder.decode([TaskItem].self, from: data)
                return
            } catch {
                loadError = "Could not read widget-tasks.json: \(error.localizedDescription)"
                tasks = []
            }
        }
    }

    func save() {
        do {
            let data = try Self.encoder.encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loadError = "Could not write widget-tasks.json: \(error.localizedDescription)"
        }
    }

    // MARK: Mutations (each persists)

    func upsert(_ task: TaskItem) {
        var updated = task
        updated.updatedAt = Date()
        if let idx = tasks.firstIndex(where: { $0.id == updated.id }) {
            tasks[idx] = updated
        } else {
            tasks.append(updated)
        }
        save()
    }

    func delete(_ id: String) {
        tasks.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func setCompleted(_ id: String, _ completed: Bool) -> TaskItem? {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        var task = tasks[idx]
        task.completed = completed
        task.completedAt = completed ? Date() : nil
        task.updatedAt = Date()
        tasks[idx] = task
        save()
        return task
    }

    /// Records that the reminder for this task was handled (banner posted or
    /// delivery scheduled) up to `date`. Does not touch `updatedAt`.
    func markReminded(_ id: String, through date: Date) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].lastRemindedAt = date
        save()
    }

    // MARK: Queries

    /// Open tasks, soonest due first (no due date sorts last), then highest
    /// priority first, then most recently created first.
    var openTasks: [TaskItem] {
        tasks.filter { !$0.completed }.sorted {
            let a = ($0.dueDate ?? .distantFuture, -$0.priority.rawValue, $0.createdAt)
            let b = ($1.dueDate ?? .distantFuture, -$1.priority.rawValue, $1.createdAt)
            return a < b
        }
    }

    /// Completed tasks, most recently completed first.
    var completedTasks: [TaskItem] {
        tasks.filter { $0.completed }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func isDueToday(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        guard let due = task.dueDate, due > now else { return false }
        return calendar.isDateInToday(due)
    }

    var overdueCount: Int {
        let now = Date()
        return openTasks.filter { ($0.dueDate ?? .distantFuture) < now }.count
    }

    var dueTodayCount: Int {
        let now = Date()
        let calendar = Calendar.current
        return openTasks.filter { isDueToday($0, now: now, calendar: calendar) }.count
    }

    /// Tasks due within the next 24 hours (including overdue) — badge/menu bar count.
    var dueSoonCount: Int {
        let now = Date()
        return openTasks.filter {
            guard let due = $0.dueDate else { return false }
            return due <= now.addingTimeInterval(24 * 3600)
        }.count
    }

    /// Due-soon tasks ordered soonest first (for the menu bar quick list).
    var dueSoonTasks: [TaskItem] {
        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)
        return openTasks
            .filter { ($0.dueDate ?? .distantPast) <= horizon }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    // MARK: Helpers

    static func dueText(for due: Date, relativeTo now: Date = Date(), formatter: RelativeDateTimeFormatter) -> String {
        if due < now {
            return "Overdue · \(formatter.localizedString(for: due, relativeTo: now))"
        }
        return "Due \(formatter.localizedString(for: due, relativeTo: now))"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Epoch milliseconds round-trips exactly; ISO8601 drops sub-second
        // precision, which breaks equality checks after a save/reload cycle.
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}
