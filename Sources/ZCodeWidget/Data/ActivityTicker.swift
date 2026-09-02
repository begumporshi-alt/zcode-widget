import Foundation

/// One observed API-call completion, as shown by the activity ticker.
struct TickerEntry: Identifiable, Equatable {
    let id: String
    let model: String
    let input: Int
    let output: Int
    let total: Int
    let date: Date
}

/// Tracks the latest ZCode activity from the token-tail stream + DB polling.
/// Dedupes by record id so the 5s poll fallback doesn't re-emit the same row.
@MainActor
final class ActivityTicker: ObservableObject {
    @Published var current: TickerEntry?
    @Published private(set) var recent: [TickerEntry] = []

    private var watcher: TokenTailWatcher?
    private var lastId: String?

    init() {
        watcher = TokenTailWatcher()
        watcher?.onNewRecord = { [weak self] record in
            Task { @MainActor in
                self?.ingest(record)
            }
        }
    }

    private func ingest(_ record: UsageRecord) {
        guard record.id != lastId else { return }
        lastId = record.id

        let entry = TickerEntry(
            id: record.id,
            model: Self.shortModel(record.modelId),
            input: record.inputTokens,
            output: record.outputTokens,
            total: record.computedTotalTokens,
            date: record.createdAt
        )
        current = entry
        recent.insert(entry, at: 0)
        if recent.count > 5 {
            recent.removeLast()
        }
    }

    /// "provider/model" or "a/b/model" ids → last path component, e.g. "free".
    static func shortModel(_ modelId: String) -> String {
        guard let last = modelId.split(separator: "/").last, !last.isEmpty else { return modelId }
        return String(last)
    }
}
