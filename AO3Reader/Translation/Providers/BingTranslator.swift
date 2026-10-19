import Foundation

/// 微軟翻譯（Bing）：
/// - `.edgeFree`：使用 Edge 瀏覽器內建翻譯的匿名權杖，免金鑰（非官方介面，可能變更）
/// - `.azure`：使用者自己的 Azure Translator 金鑰與區域
struct BingTranslator: TranslationProvider {
    enum Auth: Sendable {
        case edgeFree
        case azure(key: String, region: String)
    }

    let auth: Auth

    var cacheIdentifier: String { "bing" }
    /// 官方單次上限 50,000 字元、1,000 段，這裡保守取值
    var maxBatchCharacters: Int { 8000 }

    private struct Item: Encodable { let Text: String }
    private struct Result: Decodable {
        struct Translation: Decodable { let text: String }
        let translations: [Translation]
    }

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let host: String
        var headers: [String: String] = [:]
        switch auth {
        case .edgeFree:
            host = "https://api-edge.cognitive.microsofttranslator.com"
            headers["Authorization"] = "Bearer \(try await EdgeTokenStore.shared.token())"
        case .azure(let key, let region):
            host = "https://api.cognitive.microsofttranslator.com"
            headers["Ocp-Apim-Subscription-Key"] = key
            if !region.isEmpty { headers["Ocp-Apim-Subscription-Region"] = region }
        }

        var components = URLComponents(string: host + "/translate")!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: Self.microsoftCode(target.code)),
        ]
        if let source {
            components.queryItems?.append(URLQueryItem(name: "from", value: Self.microsoftCode(source.code)))
        }

        let data = try await HTTP.postJSON(components.url!, headers: headers, body: texts.map(Item.init(Text:)))
        let results = try JSONDecoder().decode([Result].self, from: data).map { $0.translations.first?.text ?? "" }
        guard results.count == texts.count else {
            throw TranslationError.countMismatch(expected: texts.count, got: results.count)
        }
        return results
    }

    /// 微軟以文字系統區分中文：zh-Hant / zh-Hans。
    static func microsoftCode(_ code: String) -> String {
        switch code {
        case "zh-TW", "zh-HK": "zh-Hant"
        case "zh-CN": "zh-Hans"
        default: code
        }
    }
}

/// Edge 翻譯權杖約 10 分鐘有效，快取以免每批都重新取得。
actor EdgeTokenStore {
    static let shared = EdgeTokenStore()

    private var token: String?
    private var expiry = Date.distantPast

    func token() async throws -> String {
        if let token, Date() < expiry { return token }
        let request = URLRequest(url: URL(string: "https://edge.microsoft.com/translate/auth")!)
        let data = try await HTTP.send(request)
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TranslationError.malformedResponse("empty Bing token") }
        token = value
        expiry = Date().addingTimeInterval(8 * 60)
        return value
    }
}
