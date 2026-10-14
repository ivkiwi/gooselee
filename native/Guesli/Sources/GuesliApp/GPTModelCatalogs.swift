import Foundation

/// Live GPT model lists for the settings menus. Hardcoded `SummaryModelPreset` lists stay the fallback.
enum ChatGPTModelCatalog {
    private struct Response: Decodable {
        let models: [Model]
    }

    private struct Model: Decodable {
        let slug: String
        let displayName: String?
        let visibility: String?
        let priority: Int?
    }

    /// Parses the Codex `models` response (the same shape Codex caches in `~/.codex/models_cache.json`).
    static func presets(from data: Data) throws -> [SummaryModelPreset] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let listed = try decoder.decode(Response.self, from: data).models.filter { (model: Model) -> Bool in
            model.visibility == "list" && !model.slug.contains("codex") && !model.slug.contains("review")
        }
        let sorted = listed.sorted { (lhs: Model, rhs: Model) -> Bool in
            (lhs.priority ?? Int.max, lhs.slug) < (rhs.priority ?? Int.max, rhs.slug)
        }
        return sorted.map { SummaryModelPreset(id: $0.slug, label: $0.displayName ?? $0.slug) }
    }
}

enum OpenAIModelCatalog {
    private struct Response: Decodable {
        let data: [Model]
    }

    private struct Model: Decodable {
        let id: String
        let created: Int?
    }

    private static let nonTextMarkers = [
        "audio", "realtime", "transcribe", "tts", "search", "image", "embedding", "instruct",
    ]

    /// Parses `GET /v1/models`, keeping text GPT models, newest first.
    static func presets(from data: Data) throws -> [SummaryModelPreset] {
        let textModels = try JSONDecoder().decode(Response.self, from: data).data.filter { (model: Model) -> Bool in
            model.id.hasPrefix("gpt-") && !nonTextMarkers.contains { model.id.contains($0) }
                && model.id.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil // dated snapshots
        }
        let sorted = textModels.sorted { (lhs: Model, rhs: Model) -> Bool in
            (lhs.created ?? 0, lhs.id) > (rhs.created ?? 0, rhs.id)
        }
        return sorted.map { SummaryModelPreset(id: $0.id, label: $0.id) }
    }
}

/// Fetches the catalogs and keeps the last good result in memory for the app's lifetime.
@MainActor
enum GPTModelCatalogClient {
    // Same endpoint Codex CLI uses with ChatGPT sign-in. client_version is required and hides models that need
    // a newer client; a high value lists every model (checked 2026-10-14: same list as Codex, 400 without it).
    private static let chatGPTModelsURL = URL(string: "https://chatgpt.com/backend-api/codex/models?client_version=999.0.0")!
    private static let openAIModelsURL = URL(string: "https://api.openai.com/v1/models")!

    private(set) static var cachedChatGPTPresets: [SummaryModelPreset] = []
    private(set) static var cachedOpenAIPresets: [SummaryModelPreset] = []

    /// Returns the cached list unchanged when signed out, offline or the response is unusable.
    static func refreshChatGPTPresets() async -> [SummaryModelPreset] {
        do {
            let (token, accountId) = try await ChatGPTAuthManager.shared.validAccessToken()
            var request = URLRequest(url: chatGPTModelsURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if !accountId.isEmpty {
                request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            let presets = try ChatGPTModelCatalog.presets(from: try await responseData(for: request))
            if !presets.isEmpty { cachedChatGPTPresets = presets }
        } catch {
            DiagnosticsLog.write("[model-catalog] ChatGPT models unavailable: \(error.localizedDescription)")
        }
        return cachedChatGPTPresets
    }

    static func refreshOpenAIPresets(apiKey: String) async -> [SummaryModelPreset] {
        guard !apiKey.isEmpty else { return cachedOpenAIPresets }
        do {
            var request = URLRequest(url: openAIModelsURL)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let presets = try OpenAIModelCatalog.presets(from: try await responseData(for: request))
            if !presets.isEmpty { cachedOpenAIPresets = presets }
        } catch {
            DiagnosticsLog.write("[model-catalog] OpenAI models unavailable: \(error.localizedDescription)")
        }
        return cachedOpenAIPresets
    }

    private static func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
