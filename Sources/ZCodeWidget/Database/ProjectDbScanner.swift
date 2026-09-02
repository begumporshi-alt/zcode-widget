import Foundation
import GRDB

/// Discovers working projects (ZCode session history + pinned folders) and
/// builds a read-only inventory of each project's database layer by parsing
/// migration/schema SQL files, detecting connection hints (key NAMES only,
/// values are never read) and collecting blueprint-ish docs.
///
/// Everything is home-relative and safe to run on any machine.
final class ProjectDbScanner {

    // MARK: - Internal model

    private struct ProjectMeta {
        let directory: String
        let sessions: Int
        let lastActivityMs: Int64?
        let pinned: Bool
    }

    private struct SQLFile {
        let path: String
    }

    private struct TableAcc {
        var tableName = ""
        var columns: [String: String] = [:]   // column name -> type
        var columnOrder: [String] = []
        var rlsEnabled = false
    }

    private struct PolicyAcc {
        let name: String
        let table: String
        let command: String
        let roles: [String]
    }

    private struct Accum {
        var tables: [String: TableAcc] = [:]  // lowercase table name -> acc
        var policies: [String: PolicyAcc] = [:]
        var functions: [String: String] = [:] // name -> "returns …"
        var triggers: [String: String] = [:]  // name -> "BEFORE … ON …"
    }

    // MARK: - State

    private let fm = FileManager.default
    private let home: URL

    private let sqlSkipDirs: Set<String> = [
        ".git", ".svn", "node_modules", "_reference", "backup", "backups",
        "archive", "archives", ".build", "build", "dist", ".next",
        ".mimosa", ".zcode", ".superpowers", "migrations_old"
    ]

    private static let envFiles = [".env", ".env.local", ".env.development", ".env.production"]

    private static let envKeyLabels: [String: String] = [
        "NEXT_PUBLIC_SUPABASE_URL": "Supabase project URL",
        "SUPABASE_URL": "Supabase project URL",
        "NEXT_PUBLIC_SUPABASE_ANON_KEY": "Supabase anon key",
        "SUPABASE_ANON_KEY": "Supabase anon key",
        "NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY": "Supabase service-role key",
        "SUPABASE_SERVICE_ROLE_KEY": "Supabase service-role key",
        "NEXT_PUBLIC_SUPABASE_DB_URL": "Direct Postgres URL",
        "SUPABASE_DB_URL": "Direct Postgres URL",
        "DATABASE_URL": "Direct Postgres URL",
        "DIRECT_URL": "Direct Postgres URL",
        "POSTGRES_URL": "Postgres connection URL",
        "POSTGRES_PRISMA_URL": "Postgres connection URL (Prisma)",
        "PGHOST": "Postgres host",
        "DB_HOST": "Postgres host",
        "SUPABASE_PROJECT_ID": "Supabase project ref",
        "NEXT_PUBLIC_SUPABASE_PROJECT_ID": "Supabase project ref"
    ]

    init() {
        home = FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Public API

    /// Scans everything; returns projects ordered by most recent session
    /// activity first (pinned projects that aren't in session history follow).
    func scan(pinnedDirs: [String]) -> [DbProject] {
        var metas: [ProjectMeta] = []
        var seen = Set<String>()

        for meta in sessionProjectMetas() where seen.insert(meta.directory).inserted {
            metas.append(meta)
        }
        for dir in pinnedDirs.map({ ($0 as NSString).standardizingPath }) where !seen.contains(dir) {
            seen.insert(dir)
            metas.append(ProjectMeta(directory: dir, sessions: 0, lastActivityMs: nil, pinned: true))
        }

        // Drop session projects nested inside another project (e.g. <proj>/docs).
        metas = dropNested(metas)

        var projects: [DbProject] = []
        for meta in metas {
            if let project = scanProject(meta) {
                projects.append(project)
            }
        }
        return projects
    }

    // MARK: - Discovery

    private func sessionProjectMetas() -> [ProjectMeta] {
        let queue = Database.shared.queue
        guard let rows = try? queue.read({ db in
            try Row.fetchAll(db, sql: """
                SELECT directory, COUNT(*) AS sessions, MAX(time_updated) AS last_activity_ms
                FROM session
                WHERE directory IS NOT NULL AND directory != '' AND time_archived IS NULL
                GROUP BY directory
                ORDER BY last_activity_ms DESC
                LIMIT 12
                """)
        }) else { return [] }

        return rows.compactMap { row in
            guard let dir: String = row["directory"], !dir.isEmpty else { return nil }
            let sessions: Int64? = row["sessions"]
            let lastMs: Int64? = row["last_activity_ms"]
            return ProjectMeta(directory: dir,
                               sessions: Int(sessions ?? 0),
                               lastActivityMs: lastMs,
                               pinned: false)
        }
    }

    private func dropNested(_ metas: [ProjectMeta]) -> [ProjectMeta] {
        metas.filter { meta in
            !metas.contains { other in
                other.directory != meta.directory
                    && meta.directory.hasPrefix(other.directory + "/")
            }
        }
    }

    // MARK: - Per-project scan

    private func scanProject(_ meta: ProjectMeta) -> DbProject? {
        let dir = (meta.directory as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }

        var accum = Accum()
        let sqlFiles = collectSQLFiles(at: dir)
        for file in sqlFiles {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: file.path), options: .mappedIfSafe),
                  data.count <= 2_000_000,
                  let text = String(data: data, encoding: .utf8) else { continue }
            parse(sql: text, into: &accum)
        }

        let displayPath = (dir as NSString).abbreviatingWithTildeInPath
        let displayName = (dir as NSString).lastPathComponent

        return DbProject(
            directory: dir,
            displayName: displayName.isEmpty ? displayPath : displayName,
            displayPath: displayPath,
            isPinned: meta.pinned,
            sessionCount: meta.sessions,
            lastActivityMs: meta.lastActivityMs,
            migrationFileCount: sqlFiles.count,
            tables: builtTables(accum.tables),
            policies: accum.policies.values.map {
                DbPolicyInfo(name: $0.name, table: $0.table, command: $0.command, roles: $0.roles)
            },
            functions: accum.functions.map { DbRoutineInfo(name: $0.key, details: $0.value) },
            triggers: accum.triggers.map { DbRoutineInfo(name: $0.key, details: $0.value) },
            connections: detectConnections(at: dir),
            docs: collectDocs(at: dir)
        )
    }

    private func builtTables(_ accs: [String: TableAcc]) -> [DbTableInfo] {
        accs.map { _, acc in
            DbTableInfo(
                name: acc.tableName,
                columns: acc.columnOrder.map { DbColumnInfo(name: $0, type: acc.columns[$0] ?? "") },
                rlsEnabled: acc.rlsEnabled
            )
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - SQL file collection

    private func collectSQLFiles(at root: String) -> [SQLFile] {
        let rootURL = URL(fileURLWithPath: root)
        guard let enumerator = fm.enumerator(at: rootURL,
                                             includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else { return [] }

        var files: [SQLFile] = []
        var seenStems = Set<String>()

        for case let url as URL in enumerator {
            guard files.count < 400 else { break }

            let rel = url.path.hasPrefix(root + "/") ? String(url.path.dropFirst(root.count + 1)) : url.lastPathComponent
            let comps = rel.split(separator: "/").map(String.init)
            let dirs = comps.dropLast()
            let filename = comps.last ?? ""

            if dirs.contains(where: { sqlSkipDirs.contains($0) }) { continue }
            guard filename.lowercased().hasSuffix(".sql") else { continue }

            let isSchemaFile = filename.lowercased() == "schema.sql"
            let inMigrations = dirs.contains("migrations")
            let inSqlDir = dirs.last == "sql"
            guard isSchemaFile || inMigrations || inSqlDir else { continue }

            // Dedupe by normalized stem ("2026…_core.sql.sql" == "2026…_core.sql").
            var stem = filename.lowercased()
            while stem.hasSuffix(".sql") { stem = String(stem.dropLast(4)) }
            guard seenStems.insert(stem).inserted else { continue }

            files.append(SQLFile(path: url.path))
        }

        return files.sorted { $0.path < $1.path }
    }

    // MARK: - SQL parsing

    /// Replaces comments, string literals and dollar-quoted bodies with spaces
    /// (keeping quoted identifiers) so keyword regexes and paren counting are safe.
    private func sanitize(_ sql: String) -> String {
        let chars = Array(sql)
        var out = [Character]()
        out.reserveCapacity(chars.count)
        var i = 0
        let n = chars.count

        while i < n {
            let c = chars[i]
            if c == "-", i + 1 < n, chars[i + 1] == "-" {
                while i < n, chars[i] != "\n" { i += 1 }
            } else if c == "/", i + 1 < n, chars[i + 1] == "*" {
                i += 2
                while i + 1 < n, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 1
                if i < n { i += 1 }
            } else if c == "'" {
                i += 1
                while i < n {
                    if chars[i] == "'" {
                        if i + 1 < n, chars[i + 1] == "'" { out.append(" "); i += 2; continue }
                        i += 1
                        break
                    }
                    out.append(" ")
                    i += 1
                }
            } else if c == "\"" {
                out.append("\"")
                i += 1
                while i < n {
                    if chars[i] == "\"" {
                        if i + 1 < n, chars[i + 1] == "\"" { out.append(" "); i += 2; continue }
                        out.append("\"")
                        i += 1
                        break
                    }
                    let ch = chars[i]
                    out.append(ch.isLetter || ch.isNumber || ch == " " || ch == "_" ? ch : " ")
                    i += 1
                }
            } else if c == "$", let end = dollarQuoteEnd(chars, from: i) {
                while i < end { out.append(" "); i += 1 }
            } else {
                out.append(c)
                i += 1
            }
        }
        return String(out)
    }

    private func dollarQuoteEnd(_ chars: [Character], from start: Int) -> Int? {
        let n = chars.count
        var j = start + 1
        while j < n, j - start < 24, chars[j] != "$" {
            guard chars[j].isLetter || chars[j].isNumber || chars[j] == "_" else { return nil }
            j += 1
        }
        guard j < n, chars[j] == "$" else { return nil }
        let delim = String(chars[start...j])
        var k = j + 1
        while k + delim.count <= n {
            if String(chars[k..<(k + delim.count)]) == delim { return k + delim.count }
            k += 1
        }
        return nil
    }

    private func parse(sql: String, into accum: inout Accum) {
        let text = sanitize(sql)
        parseTables(text, into: &accum)
        parsePolicies(text, into: &accum)
        parseFunctions(text, into: &accum)
        parseTriggers(text, into: &accum)
    }

    // MARK: Tables

    private static let tablePattern = try! NSRegularExpression(
        pattern: #"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:[a-z_$][a-z0-9_$]*\.)?(?:"([^"]+)"|([a-z_$][a-z0-9_$]*))"#,
        options: [.caseInsensitive]
    )
    private static let rlsEnablePattern = try! NSRegularExpression(
        pattern: #"alter\s+table\s+(?:if\s+exists\s+)?(?:[a-z_$][a-z0-9_$]*\.)?(?:"([^"]+)"|([a-z_$][a-z0-9_$]*))\s+enable\s+row\s+level\s+security"#,
        options: [.caseInsensitive]
    )
    private static let wordPattern = try! NSRegularExpression(
        pattern: #"(?:"([^"]+)"|([a-zA-Z_$][a-zA-Z0-9_$]*))"#
    )

    private static let columnTypeKeywords: Set<String> = [
        "constraint", "primary", "unique", "foreign", "check", "references",
        "not", "default", "generated", "as", "identity", "collate"
    ]

    private func parseTables(_ text: String, into accum: inout Accum) {
        let ns = text as NSString
        for match in Self.tablePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let name = captureName(from: match, ns: ns, quoted: 1, plain: 2) else { continue }
            let key = name.lowercased()

            var table = accum.tables[key] ?? TableAcc()
            if table.tableName.isEmpty { table.tableName = name }

            // Locate the opening paren soon after the name (ignoring
            // "CREATE TABLE … AS SELECT", which has no column body).
            let distance = min(200, ns.length - match.range.upperBound)
            let search = NSRange(location: match.range.upperBound, length: distance)
            let open = ns.range(of: "(", options: [], range: search)
            if open.location != NSNotFound {
                let between = ns.substring(with: NSRange(location: match.range.upperBound,
                                                         length: open.location - match.range.upperBound)).lowercased()
                if !between.contains(" as "),
                   let bodyRange = parenBodyRange(ns, open: open.location) {
                    addColumns(ns.substring(with: bodyRange), into: &table)
                }
            }
            accum.tables[key] = table
        }

        for match in Self.rlsEnablePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let name = captureName(from: match, ns: ns, quoted: 1, plain: 2) else { continue }
            let key = name.lowercased()
            if accum.tables[key] == nil {
                var acc = TableAcc()
                acc.tableName = name
                acc.rlsEnabled = true
                accum.tables[key] = acc
            } else {
                accum.tables[key]?.rlsEnabled = true
            }
        }
    }

    private func addColumns(_ body: String, into table: inout TableAcc) {
        for segment in topLevelSplit(body) {
            guard let column = parseColumn(segment) else { continue }
            let colKey = column.name.lowercased()
            if table.columns[colKey] == nil {
                table.columnOrder.append(column.name)
            }
            table.columns[colKey] = column.type
        }
    }

    private func parseColumn(_ segment: String) -> (name: String, type: String)? {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        let constraintPrefixes = ["constraint", "primary key", "unique", "foreign key",
                                  "check", "exclude", "like ", "period"]
        if constraintPrefixes.contains(where: { lowered.hasPrefix($0) }) { return nil }

        let ns = trimmed as NSString
        guard let nameMatch = Self.wordPattern.firstMatch(in: trimmed,
                                                          range: NSRange(location: 0, length: ns.length)),
              let name = captureName(from: nameMatch, ns: ns, quoted: 1, plain: 2) else { return nil }

        let after = NSRange(location: nameMatch.range.upperBound, length: ns.length - nameMatch.range.upperBound)
        guard let typeMatch = Self.wordPattern.firstMatch(in: trimmed, range: after),
              let type = captureName(from: typeMatch, ns: ns, quoted: 1, plain: 2) else {
            return (name, "")
        }
        if Self.columnTypeKeywords.contains(type.lowercased()) { return (name, "") }
        return (name, type)
    }

    /// Range of the top-level body of a parenthesized block opening at `open`
    /// (excluding the parentheses themselves). Input is sanitized ASCII-ish.
    private func parenBodyRange(_ ns: NSString, open: Int) -> NSRange? {
        var depth = 0
        var i = open
        while i < ns.length {
            let unit = ns.character(at: i)
            if unit == 0x28 {          // (
                depth += 1
            } else if unit == 0x29 {   // )
                depth -= 1
                if depth == 0 { return NSRange(location: open + 1, length: i - open - 1) }
            }
            i += 1
        }
        return nil
    }

    /// Splits on top-level commas (paren depth 0; text is already sanitized).
    private func topLevelSplit(_ body: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for ch in body {
            if ch == "(" {
                depth += 1
            } else if ch == ")" {
                depth = max(0, depth - 1)
            } else if ch == ",", depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        parts.append(current)
        return parts
    }

    // MARK: Policies

    private static let policyPattern = try! NSRegularExpression(
        pattern: #"create\s+policy\s+(?:if\s+not\s+exists\s+)?(?:"([^"]+)"|([a-z_$][a-z0-9_$]*))\s+on\s+(?:"([^"]+)"|([a-z_$][a-z0-9_$.]*))(?:\s+as\s+(permissive|restrictive))?(?:\s+for\s+(all|select|insert|update|delete))?(?:\s+to\s+((?:public|"[^"]+"|[a-z_$][a-z0-9_$]*)(?:\s*,\s*(?:public|"[^"]+"|[a-z_$][a-z0-9_$]*))*))?"#,
        options: [.caseInsensitive]
    )

    private func parsePolicies(_ text: String, into accum: inout Accum) {
        let ns = text as NSString
        for match in Self.policyPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let name = captureName(from: match, ns: ns, quoted: 1, plain: 2) else { continue }
            let table = captureName(from: match, ns: ns, quoted: 3, plain: 4) ?? ""
            let command = match.range(at: 6).length > 0
                ? ns.substring(with: match.range(at: 6)).uppercased()
                : "ALL"
            var roles: [String] = []
            if match.range(at: 7).length > 0 {
                roles = ns.substring(with: match.range(at: 7))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "") }
                    .filter { !$0.isEmpty }
            }
            accum.policies[name.lowercased()] = PolicyAcc(name: name, table: table, command: command, roles: roles)
        }
    }

    // MARK: Functions & triggers

    private static let functionPattern = try! NSRegularExpression(
        pattern: #"create\s+(?:or\s+replace\s+)?function\s+(?:[a-z_$][a-z0-9_$]*\.)?(?:"([^"]+)"|([a-z_$][a-z0-9_$]*))"#,
        options: [.caseInsensitive]
    )
    private static let returnsPattern = try! NSRegularExpression(
        pattern: #"\breturns\s+((?:setof\s+)?(?:table|record|trigger|void|[a-z_$][a-z0-9_$.]*|"[^"]+"))"#,
        options: [.caseInsensitive]
    )
    private static let triggerPattern = try! NSRegularExpression(
        pattern: #"create\s+(?:or\s+replace\s+)?trigger\s+(?:if\s+not\s+exists\s+)?(?:"([^"]+)"|([a-z_$][a-z0-9_$]*))\s+(before|after|instead\s+of)\s+(.+?)\s+on\s+(?:"([^"]+)"|([a-z_$][a-z0-9_$.]*))"#,
        options: [.caseInsensitive]
    )

    private func parseFunctions(_ text: String, into accum: inout Accum) {
        let ns = text as NSString
        for match in Self.functionPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let name = captureName(from: match, ns: ns, quoted: 1, plain: 2) else { continue }
            // Scan for RETURNS only within this statement (up to the next ';').
            let tail = NSRange(location: match.range.upperBound, length: ns.length - match.range.upperBound)
            let semi = ns.range(of: ";", options: [], range: tail)
            let scanRange = semi.location != NSNotFound
                ? NSRange(location: tail.location, length: semi.location - tail.location)
                : tail
            var details = ""
            if let ret = Self.returnsPattern.firstMatch(in: text, range: scanRange),
               ret.range(at: 1).length > 0 {
                details = "returns " + ns.substring(with: ret.range(at: 1)).trimmingCharacters(in: .whitespaces)
            }
            accum.functions[name.lowercased()] = details
        }
    }

    private func parseTriggers(_ text: String, into accum: inout Accum) {
        let ns = text as NSString
        for match in Self.triggerPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let name = captureName(from: match, ns: ns, quoted: 1, plain: 2),
                  let table = captureName(from: match, ns: ns, quoted: 5, plain: 6) else { continue }
            let timing = ns.substring(with: match.range(at: 3)).uppercased()
            let events = ns.substring(with: match.range(at: 4)).uppercased()
            accum.triggers[name.lowercased()] = "\(timing) \(events) ON \(table)"
        }
    }

    // MARK: Shared helpers

    private func captureName(from match: NSTextCheckingResult, ns: NSString, quoted: Int, plain: Int) -> String? {
        if match.range(at: quoted).length > 0 {
            return ns.substring(with: match.range(at: quoted))
        }
        if match.range(at: plain).length > 0 {
            return ns.substring(with: match.range(at: plain))
        }
        return nil
    }

    // MARK: Connections (key names only — values are never read or stored)

    private func detectConnections(at root: String) -> [DbConnectionInfo] {
        var found: [String: String] = [:]   // label -> source file
        let keyPattern = try! NSRegularExpression(
            pattern: #"(?m)^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*="#
        )

        for rel in Self.envFiles {
            let path = root + "/" + rel
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                  data.count <= 16_384,
                  let text = String(data: data, encoding: .utf8) else { continue }
            let ns = text as NSString
            for match in keyPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard match.range(at: 1).length > 0 else { continue }
                let key = ns.substring(with: match.range(at: 1))
                if let label = Self.envKeyLabels[key], found[label] == nil {
                    found[label] = rel
                }
            }
        }

        let configToml = root + "/supabase/config.toml"
        if fm.fileExists(atPath: configToml) {
            found["Supabase CLI config (config.toml)"] = "supabase/config.toml"
        }

        for rel in ["docker-compose.yml", "docker-compose.yaml", "docker/docker-compose.yml"] {
            let path = root + "/" + rel
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                  data.count <= 8_192,
                  let text = String(data: data, encoding: .utf8) else { continue }
            let lowered = text.lowercased()
            if lowered.contains("postgres"), lowered.contains("services") {
                found["Postgres service (docker-compose)"] = rel
                break
            }
        }

        return found.map { DbConnectionInfo(label: $0.key, source: $0.value) }
            .sorted { $0.label < $1.label }
    }

    // MARK: Blueprints & docs

    private func collectDocs(at dir: String) -> [DbDocInfo] {
        var docs: [DbDocInfo] = []

        // ZCode memory project for this folder (slug = slugified folder name).
        let slug = slugify((dir as NSString).lastPathComponent)
        let memoriesRoot = home.appendingPathComponent(".zcode/cli/memories/projects").path
        if let memoryDirs = try? fm.contentsOfDirectory(atPath: memoriesRoot) {
            let prefix = slug + "-"
            for memoryDir in memoryDirs where memoryDir.hasPrefix(prefix) {
                let memoryFolder = memoriesRoot + "/" + memoryDir + "/memory"
                guard var files = try? fm.contentsOfDirectory(atPath: memoryFolder) else { continue }
                files = files.filter { $0.lowercased().hasSuffix(".md") && $0.lowercased() != "memory.md" }
                for file in newestFirst(files, in: memoryFolder).prefix(10) {
                    docs.append(docInfo(path: memoryFolder + "/" + file, kind: "memory"))
                }
            }
        }

        // In-repo markdown: docs/ folder + architecture-ish files at the root.
        let docsFolder = dir + "/docs"
        if var files = try? fm.contentsOfDirectory(atPath: docsFolder) {
            files = files.filter { $0.lowercased().hasSuffix(".md") }
            for file in newestFirst(files, in: docsFolder).prefix(6) {
                docs.append(docInfo(path: docsFolder + "/" + file, kind: "repo"))
            }
        }
        if let rootFiles = try? fm.contentsOfDirectory(atPath: dir) {
            let interesting = rootFiles.filter { file in
                let lower = file.lowercased()
                guard lower.hasSuffix(".md") else { return false }
                let base = (lower as NSString).deletingPathExtension
                return base.hasPrefix("architecture") || base.hasPrefix("blueprint")
                    || base.hasPrefix("design") || base.hasPrefix("schema")
            }
            for file in newestFirst(interesting, in: dir).prefix(4) {
                docs.append(docInfo(path: dir + "/" + file, kind: "repo"))
            }
        }
        return docs
    }

    private func newestFirst(_ files: [String], in folder: String) -> [String] {
        files.sorted { a, b in
            let da = modificationDate(of: folder + "/" + a)
            let db = modificationDate(of: folder + "/" + b)
            return (da ?? .distantPast) > (db ?? .distantPast)
        }
    }

    private func modificationDate(of path: String) -> Date? {
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    private func docInfo(path: String, kind: String) -> DbDocInfo {
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let lowerTitle = title.lowercased()
        let tag: String? = (lowerTitle.contains("architect") || lowerTitle.contains("blueprint") || lowerTitle.contains("design"))
            ? "blueprint"
            : nil

        var summary = ""
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
            let head = String(decoding: data.prefix(2000), as: UTF8.self)
            summary = firstLine(head)
        }
        return DbDocInfo(title: title, kind: kind, tag: tag, summary: summary)
    }

    /// First informative line: frontmatter `description:`, first heading, or first non-empty line.
    private func firstLine(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<close] where line.lowercased().hasPrefix("description:") {
                return String(line.dropFirst("description:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .truncated(220)
            }
            lines = Array(lines[(close + 1)...])
        }
        for line in lines {
            if line.isEmpty { continue }
            let headingless = line.hasPrefix("#") ? line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) : line
            if !headingless.isEmpty { return headingless.truncated(220) }
        }
        return ""
    }

    private func slugify(_ name: String) -> String {
        var out = ""
        for ch in name.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        return out
    }
}

private extension String {
    func truncated(_ max: Int) -> String {
        count <= max ? self : String(prefix(max - 1)) + "…"
    }
}
