import SwiftUI

/// Slim live strip pinned to the bottom of the panel: a pulse dot plus the
/// most recent API-call completion (model, tokens, relative time).
struct ActivityTickerBar: View {
    @ObservedObject var ticker: ActivityTicker

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(at: context.date))
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor(at: context.date).opacity(0.5), radius: 2)

                if let current = ticker.current {
                    Text("\(current.model) · \(formatTokens(current.input)) in → \(formatTokens(current.output)) out · \(current.total > 0 ? formatTokens(current.total) : "") total")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(relativeTime(current.date, at: context.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("watching for activity…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .id(ticker.current?.id)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.25), value: ticker.current?.id)
    }

    /// Green while the last record is fresh (< 30s), gray once stale.
    private func statusColor(at now: Date) -> Color {
        guard let current = ticker.current else { return .gray }
        return now.timeIntervalSince(current.date) < 30 ? .green : .gray
    }

    private func relativeTime(_ date: Date, at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
