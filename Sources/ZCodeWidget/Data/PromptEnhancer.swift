import Foundation

/// Result of a successful prompt enhancement.
struct EnhancedPrompt: Equatable {
    let text: String
    let providerName: String
    let model: String
}

enum EnhanceError: LocalizedError {
    case noProvider
    case noModel(String)
    case invalidBaseURL
    case badResponse(String)
    case network(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "No enabled provider found in ~/.zcode/v2/config.json"
        case .noModel(let name):
            return "Provider \(name) has no models configured"
        case .invalidBaseURL:
            return "Provider has an invalid base URL"
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .http(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}

/// Calls the user's configured ZCode provider (anthropic or openai-compatible)
/// to rewrite a prompt. Reads the provider registry via ProviderConfigStore and
/// forwards the provider's custom headers, so the agentrouter setup keeps working.
final class PromptEnhancer {
    private let store: ProviderConfigStore

    init(store: ProviderConfigStore = ProviderConfigStore()) {
        self.store = store
    }

    private static let systemPrompt = """
        You are an expert prompt engineer. Rewrite the user's prompt to be more effective while \
        preserving its exact intent, language, and any specific details it contains. Make it \
        concrete and actionable: add relevant context, a clear goal, constraints, and an expected \
        output format where they help. Return ONLY the rewritten prompt as plain text — no \
        preamble, no explanation, no quotes, no markdown fences.
        """

    func enhance(_ prompt: String) async throws -> EnhancedPrompt {
        store.load()
        guard let provider = Self.pickProvider(store.providers) else { throw EnhanceError.noProvider }
        let displayName = provider.name.isEmpty ? provider.id : provider.name
        guard let model = provider.models.first else { throw EnhanceError.noModel(displayName) }

        let endpoint: URL
        let body: [String: Any]
        var headers: [String: String] = ["content-type": "application/json"]

        switch provider.kind {
        case "anthropic":
            guard let url = Self.endpoint(base: provider.baseURL, path: "/messages") else {
                throw EnhanceError.invalidBaseURL
            }
            endpoint = url
            if !provider.apiKey.isEmpty { headers["x-api-key"] = provider.apiKey }
            headers["anthropic-version"] = "2023-06-01"
            body = [
                "model": model.id,
                "max_tokens": 512,
                "system": Self.systemPrompt,
                "messages": [["role": "user", "content": prompt]],
            ]
        case "openai-compatible":
            guard let url = Self.endpoint(base: provider.baseURL, path: "/chat/completions") else {
                throw EnhanceError.invalidBaseURL
            }
            endpoint = url
            if !provider.apiKey.isEmpty { headers["Authorization"] = "Bearer \(provider.apiKey)" }
            body = [
                "model": model.id,
                "max_tokens": 512,
                "messages": [
                    ["role": "system", "content": Self.systemPrompt],
                    ["role": "user", "content": prompt],
                ],
            ]
        default:
            throw EnhanceError.badResponse("unsupported provider kind '\(provider.kind)'")
        }

        // Forward the provider's custom headers (e.g. the agentrouter User-Agent fix).
        for pair in provider.headers where !pair.key.isEmpty {
            headers[pair.key] = pair.value
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.allHTTPHeaderFields = headers
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw EnhanceError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EnhanceError.badResponse("no HTTP response")
        }
        guard http.statusCode == 200 else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw EnhanceError.http(http.statusCode, snippet)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnhanceError.badResponse("body is not JSON")
        }

        var text: String?
        if provider.kind == "anthropic" {
            let content = obj["content"] as? [[String: Any]] ?? []
            text = content.compactMap { $0["text"] as? String }.joined()
        } else {
            let choices = obj["choices"] as? [[String: Any]] ?? []
            if let message = choices.first?["message"] as? [String: Any] {
                text = message["content"] as? String
            }
        }

        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnhanceError.badResponse("empty completion") }
        return EnhancedPrompt(text: trimmed, providerName: displayName, model: model.id)
    }

    /// Best enabled anthropic/openai-compatible provider: prefers one with both
    /// a base URL and an API key, then base URL only, then any compatible one.
    static func pickProvider(_ providers: [ProviderConfig]) -> ProviderConfig? {
        let compatible = providers.filter { $0.enabled && ($0.kind == "anthropic" || $0.kind == "openai-compatible") }
        let fullyConfigured = compatible.filter { !$0.baseURL.isEmpty && !$0.apiKey.isEmpty }
        if !fullyConfigured.isEmpty { return fullyConfigured.first }
        let callable = compatible.filter { !$0.baseURL.isEmpty }
        return callable.first ?? compatible.first
    }

    /// Normalizes base URL to the provider's /v1 root, e.g.
    /// https://api.example.com → https://api.example.com/v1/messages
    private static func endpoint(base: String, path: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/v1") { s += "/v1" }
        return URL(string: s + path)
    }
}
