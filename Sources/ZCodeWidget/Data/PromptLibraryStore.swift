import Foundation

/// A saved prompt snippet in the library.
struct PromptEntry: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var content: String
    var category: String  // one of PromptLibraryStore.categories
    var isBuiltin: Bool

    init(id: String = UUID().uuidString, title: String, category: String, isBuiltin: Bool = false, content: String) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.isBuiltin = isBuiltin
    }
}

/// Loads/saves ~/.zcode/prompts.json and seeds the curated built-in library.
/// The file is user-visible and editable, so it survives reinstalls and can be shared.
final class PromptLibraryStore: ObservableObject {
    @Published var prompts: [PromptEntry] = []
    @Published var loadError: String?

    /// Default: user-visible. Overridable for tests.
    static var libraryPath = NSHomeDirectory() + "/.zcode/prompts.json"
    static let categories = ["coding", "writing", "research", "system"]

    private var fileURL: URL { URL(fileURLWithPath: Self.libraryPath) }

    func load() {
        loadError = nil
        if FileManager.default.fileExists(atPath: Self.libraryPath) {
            do {
                let data = try Data(contentsOf: fileURL)
                prompts = try Self.decoder.decode([PromptEntry].self, from: data)
                return
            } catch {
                loadError = "Could not read prompts.json: \(error.localizedDescription)"
                prompts = []
            }
        }
        prompts = Self.builtins
        save()
    }

    func save() {
        do {
            let data = try Self.encoder.encode(prompts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loadError = "Could not write prompts.json: \(error.localizedDescription)"
        }
    }

    func upsert(_ entry: PromptEntry) {
        if let idx = prompts.firstIndex(where: { $0.id == entry.id }) {
            prompts[idx] = entry
        } else {
            prompts.append(entry)
        }
        save()
    }

    func remove(_ entry: PromptEntry) {
        prompts.removeAll { $0.id == entry.id }
        save()
    }

    /// Re-seed any curated built-ins the user deleted (custom entries are kept).
    func restoreDefaults() {
        for builtin in Self.builtins where !prompts.contains(where: { $0.id == builtin.id }) {
            prompts.append(builtin)
        }
        save()
    }

    /// Built-ins first, then user entries, alphabetical within each group.
    var sorted: [PromptEntry] {
        prompts.sorted {
            let lhs = ($0.isBuiltin ? 0 : 1, $0.title.lowercased())
            let rhs = ($1.isBuiltin ? 0 : 1, $1.title.lowercased())
            return lhs < rhs
        }
    }

    // MARK: - Curated library

    static let builtins: [PromptEntry] = [
        PromptEntry(id: "builtin.code-review", title: "Code Review", category: "coding", isBuiltin: true, content: """
            Review the following code for bugs, security issues, performance problems, and readability. Report each issue as: severity, location, explanation, and a suggested fix. If the code is clean, say so explicitly.

            ```
            <PASTE CODE>
            ```
            """),
        PromptEntry(id: "builtin.debug-this", title: "Debug This", category: "coding", isBuiltin: true, content: """
            I'm hitting an error and need help debugging it.

            Error: <PASTE ERROR / STACK TRACE>
            What I tried: <WHAT YOU TRIED>
            Relevant code:
            ```
            <PASTE CODE>
            ```

            Walk through the likely root causes one at a time, then propose the most probable fix with a short verification plan.
            """),
        PromptEntry(id: "builtin.refactor", title: "Refactor", category: "coding", isBuiltin: true, content: """
            Refactor the following code to improve <GOAL: readability / performance / maintainability>. Keep behavior identical unless you call out a deliberate change. Show the refactored code plus a summary of what changed and why.

            ```
            <PASTE CODE>
            ```
            """),
        PromptEntry(id: "builtin.write-tests", title: "Write Tests", category: "coding", isBuiltin: true, content: """
            Write comprehensive tests for the following code. Cover happy paths, edge cases (empty input, invalid input, boundaries), and failure modes. Follow <TEST FRAMEWORK> conventions.

            ```
            <PASTE CODE>
            ```
            """),
        PromptEntry(id: "builtin.explain-code", title: "Explain This Code", category: "coding", isBuiltin: true, content: """
            Explain the following code as if I'm a <LEVEL: junior developer / non-programmer>. Break it into logical parts: what each part does, why it exists, and how the pieces connect. Point out anything unusual or risky.

            ```
            <PASTE CODE>
            ```
            """),
        PromptEntry(id: "builtin.design-api", title: "Design an API", category: "coding", isBuiltin: true, content: """
            Design a REST API for <PRODUCT / SERVICE>. Return: resource endpoints with methods and example requests/responses, status codes, error format, auth scheme, and pagination. Flag any design tradeoffs or open questions.
            """),
        PromptEntry(id: "builtin.blog-post", title: "Blog Post", category: "writing", isBuiltin: true, content: """
            Write a blog post outline and first draft for the topic: <TOPIC>.
            Audience: <AUDIENCE>. Desired length: <LENGTH>. Tone: <TONE>.
            Include a hook, clear H2 sections, concrete examples, and a call to action.
            """),
        PromptEntry(id: "builtin.email", title: "Draft an Email", category: "writing", isBuiltin: true, content: """
            Draft an email about <SUBJECT> to <RECIPIENT>. Goal: <GOAL>. Tone: <TONE: friendly / formal / firm>. Keep it under <LENGTH> words with a clear subject line and a single ask.
            """),
        PromptEntry(id: "builtin.docs", title: "Write Docs", category: "writing", isBuiltin: true, content: """
            Write user documentation for <FEATURE / TOOL>. Cover: what it does, when to use it, how to use it step by step, common errors and fixes, and a short example. Use plain language; define any jargon you keep.
            """),
        PromptEntry(id: "builtin.deep-dive", title: "Research Deep Dive", category: "research", isBuiltin: true, content: """
            Research <TOPIC> and give me a structured brief: key facts, current state of the art, main debates, and my recommended next steps. Cite sources inline where possible and flag uncertainty explicitly.
            """),
        PromptEntry(id: "builtin.compare", title: "Compare Options", category: "research", isBuiltin: true, content: """
            Compare <OPTION A> and <OPTION B> across: cost, effort, ecosystem maturity, and fit for <MY USE CASE>. Give a clear recommendation, and state the conditions under which you'd pick each one.
            """),
        PromptEntry(id: "builtin.sql", title: "Write SQL", category: "system", isBuiltin: true, content: """
            Write a SQL query that <GOAL>. Schema: <TABLES / COLUMNS>. Return the query with a brief comment on why it's written this way, and note any indexes that would help.
            """),
        PromptEntry(id: "builtin.regex", title: "Build a Regex", category: "system", isBuiltin: true, content: """
            Write a regex that matches <PATTERN DESCRIPTION> in <LANGUAGE>. Give the expression, a short explanation of each part, and 3 test cases (matching and non-matching).
            """),
        PromptEntry(id: "builtin.security-review", title: "Security Review", category: "system", isBuiltin: true, content: """
            Perform a security review of the following code. Check against OWASP categories: injection, auth, session management, XSS, SSRF, deserialization, secrets. For each finding: severity, exploit scenario, and remediation.

            ```
            <PASTE CODE>
            ```
            """),
        PromptEntry(id: "builtin.summarize", title: "Summarize", category: "system", isBuiltin: true, content: """
            Summarize the following text in <LENGTH: 3 bullet points / 100 words>. Preserve all key facts, numbers, and caveats. Flag anything that reads as opinion vs fact.

            <PASTE TEXT>
            """),
    ]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()
}
