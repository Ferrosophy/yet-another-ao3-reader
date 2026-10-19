import Foundation

/// 翻譯服務的統一介面。輸入為段落陣列，輸出必須是一一對應、順序相同的譯文陣列，
/// 這樣閱讀器才能把每段譯文放在原文段落的正下方（沉浸式雙語對照）。
protocol TranslationProvider: Sendable {
    /// 用於翻譯快取鍵，應包含服務與模型，換模型時不會讀到舊譯文。
    var cacheIdentifier: String { get }
    /// 單一批次建議的最大字元數。
    var maxBatchCharacters: Int { get }
    func translate(_ texts: [String], to target: TranslationLanguage) async throws -> [String]
}

enum TranslationError: LocalizedError {
    case missingAPIKey(String)
    case missingModel
    case invalidBaseURL
    case server(Int, String)
    case malformedResponse(String)
    case countMismatch(expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider): "尚未設定 \(provider) 的 API Key"
        case .missingModel: "尚未填寫模型名稱"
        case .invalidBaseURL: "API 位址無效"
        case .server(let code, let message): "翻譯服務錯誤（\(code)）：\(message)"
        case .malformedResponse(let detail): "翻譯回應格式錯誤：\(detail)"
        case .countMismatch(let expected, let got): "譯文段落數不符（預期 \(expected)，實際 \(got)）"
        }
    }
}

/// 翻譯 API 共用的 HTTP 工具。
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        // 翻譯 API 不需要也不應攜帶 AO3 的 cookie
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    static func postJSON(_ url: URL, headers: [String: String] = [:], body: some Encodable) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TranslationError.server(status, errorMessage(from: data))
        }
        return data
    }

    /// 盡量從 OpenAI / Anthropic / Google 的錯誤 JSON 取出可讀訊息。
    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String { return message }
        }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }
}
