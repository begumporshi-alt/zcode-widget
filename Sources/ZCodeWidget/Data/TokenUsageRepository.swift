import Foundation
import GRDB

final class TokenUsageRepository {
    private let db: DatabaseQueue

    init(db: DatabaseQueue = Database.shared.queue) {
        self.db = db
    }

    /// Decoded row for daily aggregates. FetchableRecord maps columns by name.
    private struct DailyRow: FetchableRecord, Decodable {
        let day: String
        let input_tokens: Int
        let output_tokens: Int
        let computed_total: Int
    }

    /// Decoded row for per-model aggregates
    private struct ModelTotalRow: FetchableRecord, Decodable {
        let model_id: String
        let computed_total: Int
    }

    /// Last N turn records for sparkline
    func recentTurns(limit: Int = 20) throws -> [TurnRecord] {
        try db.read { db in
            try TurnRecord
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
                .reversed()  // oldest first for chart ordering
        }
    }

    /// Last N model_usage rows (for the tail ring buffer)
    func recentUsage(limit: Int = 200) throws -> [UsageRecord] {
        try db.read { db in
            try UsageRecord
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
                .reversed()
        }
    }

    /// Daily totals for the last `days`. `started_at` is millisecond epoch.
    func dailyTotals(days: Int = 7) throws -> [DailyUsage] {
        try db.read { db in
            // SQLite's date() takes seconds, our column is milliseconds → divide by 1000.
            let cutoffMs = Int64(Calendar.current.date(byAdding: .day, value: -days, to: Date())!.timeIntervalSince1970 * 1000)
            let rows = try DailyRow.fetchAll(db, sql: """
                SELECT
                    date(started_at / 1000, 'unixepoch') as day,
                    COALESCE(SUM(input_tokens), 0) as input_tokens,
                    COALESCE(SUM(output_tokens), 0) as output_tokens,
                    COALESCE(SUM(computed_total_tokens), 0) as computed_total
                FROM turn_usage
                WHERE started_at >= ?
                GROUP BY day
                ORDER BY day ASC
                """, arguments: [cutoffMs])

            return rows.map { row in
                DailyUsage(
                    date: row.day,
                    inputTokens: row.input_tokens,
                    outputTokens: row.output_tokens,
                    computedTotal: row.computed_total
                )
            }
        }
    }

    /// All-time totals
    func totals() throws -> UsageTotals {
        try db.read { db in
            let totalInput = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(input_tokens), 0) FROM turn_usage") ?? 0
            let totalOutput = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(output_tokens), 0) FROM turn_usage") ?? 0
            let totalComputed = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(computed_total_tokens), 0) FROM turn_usage") ?? 0
            let callCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM turn_usage") ?? 0
            return UsageTotals(
                totalInput: totalInput,
                totalOutput: totalOutput,
                totalComputed: totalComputed,
                callCount: callCount
            )
        }
    }

    /// Number of turns in the last `days`
    func turnCount(days: Int = 7) throws -> Int {
        try db.read { db in
            let cutoffMs = Int64(Calendar.current.date(byAdding: .day, value: -days, to: Date())!.timeIntervalSince1970 * 1000)
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM turn_usage WHERE started_at >= ?", arguments: [cutoffMs]) ?? 0
        }
    }

    /// Token totals per model over the last `days` (from model_usage), best first
    func topModels(days: Int = 7, limit: Int = 3) throws -> [ModelTotal] {
        try db.read { db in
            let cutoffMs = Int64(Calendar.current.date(byAdding: .day, value: -days, to: Date())!.timeIntervalSince1970 * 1000)
            let rows = try ModelTotalRow.fetchAll(db, sql: """
                SELECT model_id, COALESCE(SUM(computed_total_tokens), 0) as computed_total
                FROM model_usage
                WHERE started_at >= ?
                GROUP BY model_id
                ORDER BY computed_total DESC
                LIMIT ?
                """, arguments: [cutoffMs, limit])
            return rows.map { ModelTotal(id: $0.model_id, computedTotal: $0.computed_total) }
        }
    }
}
