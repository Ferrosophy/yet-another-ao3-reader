import Foundation

/// OpenAI Chat Completions 相容介面：OpenAI、DeepSeek、OpenRouter、Groq、本地 Ollama / LM Studio 等皆可使用。
struct OpenAICompatibleBackend: ChatBackend {
    let baseURL: URL
    let apiKey: String
    let model: String

    var identifier: String { "openai:\(baseURL.host() ?? ""):\(model)" }

    private struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let temperature = 0.3
    }

    private struct Response: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
        let choices: [Choice]
    }

    func complete(system: String, user: String) async throws -> String {
        let url = baseURL.appending(path: "chat/completions")
        var headers: [String: String] = [:]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        let data = try await HTTP.postJSON(url, headers: headers, body: Request(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)]
        ))
        guard let text = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content else {
            throw TranslationError.malformedResponse("empty choices")
        }
        return text
    }
}

/// Anthropic Claude Messages API。
struct AnthropicBackend: ChatBackend {
    let apiKey: String
    let model: String

    var identifier: String { "anthropic:\(model)" }

    private struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    func complete(system: String, user: String) async throws -> String {
        let data = try await HTTP.postJSON(
            URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"],
            body: Request(model: model, max_tokens: 16_000, system: system, messages: [.init(role: "user", content: user)])
        )
        let text = try JSONDecoder().decode(Response.self, from: data).content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw TranslationError.malformedResponse("empty content") }
        return text
    }
}

/// Google Gemini generateContent API。
struct GeminiBackend: ChatBackend {
    let apiKey: String
    let model: String

    var identifier: String { "gemini:\(model)" }

    private struct Part: Codable { let text: String }
    private struct Content: Codable { var role: String?; let parts: [Part] }
    private struct Request: Encodable {
        struct Config: Encodable { let responseMimeType = "application/json"; let temperature = 0.3 }
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig = Config()
    }
    private struct Response: Decodable {
        struct Candidate: Decodable { let content: Content? }
        let candidates: [Candidate]?
    }

    func complete(system: String, user: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        let data = try await HTTP.postJSON(url, headers: ["x-goog-api-key": apiKey], body: Request(
            systemInstruction: Content(parts: [Part(text: system)]),
            contents: [Content(role: "user", parts: [Part(text: user)])]
        ))
        let text = try JSONDecoder().decode(Response.self, from: data)
            .candidates?.first?.content?.parts.map(\.text).joined() ?? ""
        guard !text.isEmpty else { throw TranslationError.malformedResponse("empty candidates") }
        return text
    }
}
