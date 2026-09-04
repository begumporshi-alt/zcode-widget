import SwiftUI
import AppKit

/// Thermal tab — macOS heat monitor & management for the widget.
///
/// Shows the current thermal state (from macOS, since raw °C needs admin
/// rights on Apple Silicon), the heaviest processes, the chats that were
/// active during a heat event, and the alert history. When hot, a cool-down
/// card offers one-click helpers (Activity Monitor / the hot chat's project).
struct ThermalView: View {
    @ObservedObject private var monitor = ThermalMonitor.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                controlsRow
                if showHelp {
                    coolDownCard
                }
                heavyProcesses
                Divider()
                alertHistory
                aboutFooter
            }
            .padding(16)
        }
        .onAppear {
            // View keeps observing the shared monitor; a manual refresh is
            // harmless if the monitor already started at launch.
        }
    }

    // MARK: Status

    private var statusCard: some View {
        let level = monitor.pressure
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ThermalMonitor.color(for: level).opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: level == .nominal ? "thermometer.medium" : "thermometer.sun.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ThermalMonitor.color(for: level))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(ThermalMonitor.levelTitle(level))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(level == .nominal ? Color.primary : ThermalMonitor.color(for: level))
                Text(statusDetail(level))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private func statusDetail(_ level: ProcessInfo.ThermalState) -> String {
        switch level {
        case .nominal: return "All clear — no thermal pressure right now."
        case .fair: return "Sustained work is warming the machine up."
        case .serious: return "The Mac is getting hot — see what's running below."
        case .critical: return "Throttling to cool down — heavy load should pause."
        @unknown default: return ""
        }
    }

    private var controlsRow: some View {
        HStack {
            Toggle("Notify when it gets hot", isOn: Binding(
                get: { monitor.alertsEnabled },
                set: { monitor.setAlertsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 11.5, weight: .medium))

            Spacer(minLength: 8)

            if !monitor.events.isEmpty {
                Button("Clear") {
                    monitor.clearHistory()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .help("Clear heat alert history")
            }
        }
    }

    // MARK: Cool-down helpers (visible near a heat event)

    private var showHelp: Bool {
        if monitor.isHot { return true }
        guard let latest = monitor.latestEvent else { return false }
        return Date().timeIntervalSince(latest.at) < 15 * 60
    }

    private var coolDownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cool-down", systemImage: "flame.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.red)
            Text("This Mac is fan-less, so it cools by throttling down. If a ZCode chat is driving the load, let it finish or pause it and give the machine a minute.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Label("Activity Monitor", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14))
                .cornerRadius(6)

                if let directory = monitor.latestEvent?.chatDirectory, FileManager.default.fileExists(atPath: directory) {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: directory))
                    } label: {
                        Label("Open hot chat's project", systemImage: "folder")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.14))
                    .cornerRadius(6)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.07))
        .cornerRadius(8)
    }

    // MARK: Heavy processes

    private var heavyProcesses: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heaviest processes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if monitor.processes.isEmpty {
                Text("Sampling CPU…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(monitor.processes.prefix(6))) { process in
                    HStack(spacing: 8) {
                        Text(String(format: "%4.0f%%", process.cpu))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(process.cpu >= 60 ? Color.red : (process.cpu >= 30 ? Color.orange : Color.primary))
                            .frame(width: 44, alignment: .trailing)
                        Text(process.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if process.isZCodeRelated {
                            Text("ZCode")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.accentColor.opacity(0.14))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }

    // MARK: Alert history

    private var alertHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heat alerts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if monitor.events.isEmpty {
                Text("No heat events yet. When the Mac runs hot (or sustains heavy load) while a chat is active, the alert appears here and as a notification — naming the hot process and the chat behind it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(monitor.events.reversed())) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: ThermalMonitor.HeatEvent) -> some View {
        let level = ProcessInfo.ThermalState(rawValue: event.level) ?? .serious
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ThermalMonitor.color(for: level))
                    .frame(width: 7, height: 7)
                Text(ThermalMonitor.levelWord(event.level))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ThermalMonitor.color(for: level))
                Text(Self.timeFormatter.string(from: event.at))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("CPU \(Int(event.peakCPU))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let culprit = event.processes.first(where: { $0.isZCodeRelated }) ?? event.processes.first {
                Text("\(culprit.name) at \(Int(culprit.cpu))% CPU")
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let chat = event.chats.first {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                    Text("'\(chat.label)'")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !chat.project.isEmpty {
                        Text(chat.project)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                    Spacer(minLength: 0)
                    if chat.requests > 1 {
                        Text("\(chat.requests) calls")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: Footer

    private var aboutFooter: some View {
        Text("Raw °C sensors need an admin password on Apple Silicon (macOS 15), so the widget watches the OS's own thermal pressure plus live CPU load, sampled every ~16 s. Alerts name the hot process and the chat that was active.")
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
