import Foundation
import GRDB

enum DatabaseError: Error {
    case notFound
    case openFailed
}

final class Database {
    static let shared = Database()

    let queue: DatabaseQueue

    private init() {
        let path = "/Users/tushershikder/.zcode/cli/db/db.sqlite"
        var config = Configuration()
        config.readonly = true
        // Read-only mode prevents lock contention with ZCode
        queue = try! DatabaseQueue(path: path, configuration: config)
    }
}