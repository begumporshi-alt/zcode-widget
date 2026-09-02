import Foundation

/// A database project: one working directory (from ZCode session history or
/// manually pinned) plus the read-only inventory of its database layer.
struct DbProject: Identifiable {
    let directory: String
    let displayName: String
    let displayPath: String
    let isPinned: Bool
    let sessionCount: Int
    let lastActivityMs: Int64?
    let migrationFileCount: Int
    let tables: [DbTableInfo]
    let policies: [DbPolicyInfo]
    let functions: [DbRoutineInfo]
    let triggers: [DbRoutineInfo]
    let connections: [DbConnectionInfo]
    let docs: [DbDocInfo]

    var id: String { directory }

    var lastActivity: Date? {
        lastActivityMs.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }

    var hasDatabaseFiles: Bool {
        migrationFileCount > 0 || !tables.isEmpty || !policies.isEmpty
            || !functions.isEmpty || !triggers.isEmpty
    }

    /// Compact count line for list rows.
    var countSummary: String {
        var parts: [String] = []
        if migrationFileCount > 0 {
            parts.append("\(migrationFileCount) migration\(migrationFileCount == 1 ? "" : "s")")
        }
        if !tables.isEmpty {
            parts.append("\(tables.count) table\(tables.count == 1 ? "" : "s")")
        }
        if !policies.isEmpty {
            parts.append("\(policies.count) RLS polic\(policies.count == 1 ? "y" : "ies")")
        }
        if !functions.isEmpty {
            parts.append("\(functions.count) function\(functions.count == 1 ? "" : "s")")
        }
        if !triggers.isEmpty {
            parts.append("\(triggers.count) trigger\(triggers.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "No database files found" : parts.joined(separator: " · ")
    }
}

/// One parsed table with its columns (best-effort schema extraction).
struct DbTableInfo: Identifiable {
    let name: String
    let columns: [DbColumnInfo]
    let rlsEnabled: Bool
    var id: String { name }
    var columnCount: Int { columns.count }
}

/// A column: name + declared type when it could be parsed.
struct DbColumnInfo: Identifiable {
    let name: String
    let type: String
    var id: String { name }
}

/// One CREATE POLICY statement.
struct DbPolicyInfo: Identifiable {
    let name: String
    let table: String
    let command: String     // SELECT / INSERT / UPDATE / DELETE / ALL
    let roles: [String]     // empty when no TO clause was present
    var id: String { name }
}

/// A function or trigger (generic so the view stays simple).
struct DbRoutineInfo: Identifiable {
    let name: String
    let details: String     // "returns uuid" | "BEFORE UPDATE ON accounts"
    var id: String { name }
}

/// A detected connection hint. Only key names are ever read — never values.
struct DbConnectionInfo: Identifiable {
    let label: String
    let source: String      // ".env", "supabase/config.toml", ...
    var id: String { label }
}

/// A blueprint-ish document: ZCode project memory or an in-repo markdown file.
struct DbDocInfo: Identifiable {
    let title: String
    let kind: String        // "memory" | "repo"
    let tag: String?        // "blueprint" when the name suggests architecture/blueprint/design
    let summary: String
    var id: String { title + kind }
}
