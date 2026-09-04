import AppKit
import GRDB

/// Sends a capture into a live ZCode chat by writing a `sendText` row into the
/// chat's own input queue (the `session_input` table of
/// `~/.zcode/cli/db/db.sqlite`) — the same channel the ZCode GUI itself uses,
/// mirrored field-for-field from a real promoted row. Nothing is ever injected
/// on its own: sends happen only when the user clicks "Send to chat". If the
/// host does not promote the externally written row within a few seconds, the
/// image is copied to the clipboard instead and the UI says so.
@MainActor
final class ChatSender {
    static let shared = ChatSender()

    struct ChatTarget: Identifiable, Equatable {
        let sessionID: String
        let title: String
        let project: String
        let directory: String?
        let isLive: Bool
        let updatedMs: Int64
        var id: String { sessionID }
        var displayLabel: String {
            if !title.isEmpty { return String(title.prefix(48)) }
            if !project.isEmpty { return project }
            return sessionID
        }
        var subLabel: String {
            if !project.isEmpty { return project }
            return directory ?? ""
        }
    }

    enum Outcome: Equatable {
        case sent
        case discarded(reason: String)
        case copied(reason: String)   // auto-send failed; clipboard fallback applied
        case noChats
        case notAnImage
    }

    struct Report: Equatable {
        let outcome: Outcome
        let chatLabel: String
    }

    private static let clientIDKey = "chatSenderClientID"

    // MARK: Recent chats

    /// Newest interactive sessions (last 7 days), live sessions first.
    /// Mirrors the Thermal monitor's read pattern: sync, best-effort.
    nonisolated static func recentChats(limit: Int = 5) -> [ChatTarget] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let cutoff = nowMs - 7 * 24 * 3600 * 1000
        var raw: [(id: String, title: String, project: String, directory: String?, updated: Int64)] = []
        do {
            try Database.shared.queue.read { db in
                let sql = """
                    SELECT id, title, project_id, directory, time_updated
                    FROM session
                    WHERE task_type = 'interactive' AND time_updated >= ?
                    ORDER BY time_updated DESC LIMIT ?
                    """
                let rows = try Row.fetchAll(db, sql: sql, arguments: [cutoff, limit * 3])
                for row in rows {
                    guard let id = row["id"] as? String else { continue }
                    raw.append((id: id,
                                title: row["title"] as? String ?? "",
                                project: row["project_id"] as? String ?? "",
                                directory: row["directory"] as? String,
                                updated: row["time_updated"] as? Int64 ?? 0))
                }
            }
        } catch {
            return []
        }
        let execBase = NSHomeDirectory() + "/.zcode/cli/exec/"
        let fm = FileManager.default
        let targets = raw.map { row -> ChatTarget in
            let live = fm.fileExists(atPath: execBase + row.id)
            return ChatTarget(sessionID: row.id,
                              title: row.title,
                              project: row.project,
                              directory: row.directory,
                              isLive: live,
                              updatedMs: row.updated)
        }
        return targets
            .sorted { (a: ChatTarget, b: ChatTarget) -> Bool in
                if a.isLive != b.isLive { return a.isLive }
                if a.updatedMs != b.updatedMs { return a.updatedMs > b.updatedMs }
                return a.sessionID < b.sessionID
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Send

    /// Auto-sends a screenshot into `target`'s chat. Completion runs on the
    /// main thread with the outcome; failures already applied the clipboard
    /// fallback by then.
    static func sendImage(_ fileURL: URL, to target: ChatTarget, completion: @escaping @MainActor (Report) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Self.enqueueImage(fileURL, target: target)
            let report = Report(outcome: outcome, chatLabel: target.displayLabel)
            DispatchQueue.main.async {
                Task { @MainActor in
                    completion(report)
                }
            }
        }
    }

    /// Videos aren't accepted as chat attachments by the queue path — copy the
    /// file so the user can attach it manually.
    nonisolated static func copyVideoToClipboard(_ fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
        pb.setString(fileURL.path, forType: .string)
    }

    nonisolated static func copyImageToClipboard(_ fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = try? Data(contentsOf: fileURL) {
            pb.setData(data, forType: .png)
        }
        pb.setString(fileURL.path, forType: .string)
    }

    // MARK: Queue injection

    private nonisolated static func enqueueImage(_ fileURL: URL, target: ChatTarget) -> Outcome {
        guard ["png", "jpg", "jpeg", "heic"].contains(fileURL.pathExtension.lowercased()) else {
            return .notAnImage
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let rowID = "queue_" + UUID().uuidString.lowercased()
        let sourceCommandID = UUID().uuidString.lowercased()
        let clientID = Self.clientID()
        let admissionSeq = Self.nextAdmissionSequence(sessionID: target.sessionID)

        // Shape mirrors a real promoted sendText payload (observed in the live
        // DB): admissionSeq is a JSON string inside intent but a number inside
        // conversationInputIntent.order; steer/dispatch start as
        // notRequested/admitted; attachments entries carry type + absolute path.
        let attachment: [String: Any] = ["type": "image", "path": fileURL.path]
        let payload: [String: Any] = [
            "text": "",
            "sourceCommandType": "sendText",
            "intent": [
                "sourceCommandId": sourceCommandID,
                "queueItemId": rowID,
                "clientId": clientID,
                "kind": "sendText",
                "admissionSeq": "\(admissionSeq)",
                "admittedAt": "\(now)",
                "requestedDelivery": "startNow",
                "admittedDelivery": "startNow",
                "attachmentRefs": [],
            ],
            "conversationInputIntent": [
                "sourceCommandId": sourceCommandID,
                "queueItemId": rowID,
                "clientId": clientID,
                "kind": "sendText",
                "text": "",
                "attachments": [attachment],
                "delivery": ["requested": "startNow", "admitted": "startNow"],
                "order": ["admissionSeq": admissionSeq],
                "steer": ["state": "notRequested"],
                "dispatch": ["state": "admitted"],
                "admittedAt": now,
            ],
            "attachments": [attachment],
        ]

        let payloadJSON: String
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let string = String(data: data, encoding: .utf8) else { return .notAnImage }
            payloadJSON = string
        } catch {
            return .copied(reason: "Couldn't build the message")
        }

        do {
            try ChatQueue.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO session_input
                        (id, session_id, kind, delivery, payload, admitted_sequence,
                         promoted_sequence, promoted_message_id, status, status_reason,
                         time_created, time_updated)
                    VALUES (?, ?, 'sendText', 'startNow', ?, ?, NULL, NULL, 'admitted', NULL, ?, ?)
                    """,
                    arguments: [rowID, target.sessionID, payloadJSON, admissionSeq, now, now])
            }
        } catch {
            copyImageToClipboard(fileURL)
            return .copied(reason: "Couldn't write into the chat queue")
        }

        // The ZCode host polls this queue and promotes rows it recognizes.
        // Give it ~20 s; anything else falls back to the clipboard.
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 1)
            let (status, reason) = Self.rowStatus(rowID)
            switch status {
            case "promoted":
                return .sent
            case "discarded", "cancelled":
                copyImageToClipboard(fileURL)
                return .copied(reason: reason ?? "ZCode rejected the message")
            default:
                continue
            }
        }
        copyImageToClipboard(fileURL)
        return .copied(reason: "ZCode didn't pick up the message")
    }

    /// Persistent client id for this widget (the GUI uses `client-<uuid>`).
    private nonisolated static func clientID() -> String {
        if let existing = UserDefaults.standard.string(forKey: clientIDKey) {
            return existing
        }
        let fresh = "client-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: clientIDKey)
        return fresh
    }

    private nonisolated static func nextAdmissionSequence(sessionID: String) -> Int64 {
        var next: Int64 = 1
        try? ChatQueue.writer.read { db in
            if let max = try Int64.fetchOne(db, sql: """
                SELECT MAX(admitted_sequence) FROM session_input WHERE session_id = ?
                """, arguments: [sessionID]) {
                next = max + 1
            }
        }
        return next
    }

    private nonisolated static func rowStatus(_ rowID: String) -> (String?, String?) {
        var status: String?
        var reason: String?
        try? ChatQueue.writer.read { db in
            if let row = try Row.fetchOne(db, sql: """
                SELECT status, status_reason FROM session_input WHERE id = ?
                """, arguments: [rowID]) {
                status = row["status"] as? String
                reason = row["status_reason"] as? String
            }
        }
        return (status, reason)
    }
}

/// The queue writer is a separate read-write connection to the live ZCode DB:
/// `Database.shared.queue` is deliberately read-only, and the host's own
/// connection is the only other writer. Short busy timeout — if the host is
/// mid-write the send simply falls back to the clipboard.
private enum ChatQueue {
    static let dbPath = NSHomeDirectory() + "/.zcode/cli/db/db.sqlite"
    static let writer: DatabaseQueue = {
        var config = Configuration()
        config.readonly = false
        config.busyMode = .timeout(3)
        return try! DatabaseQueue(path: dbPath, configuration: config)
    }()
}
