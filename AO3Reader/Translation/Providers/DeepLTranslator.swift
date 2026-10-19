import Foundation

/// DeepL：
/// - 填了金鑰 → 官方 API（DeepL API Free 金鑰以 ":fx" 結尾，每月 50 萬字免費）
/// - 未填金鑰 → 網頁版 jsonrpc 介面（非官方，限流嚴格，常回傳 429）
struct DeepLTranslator: TranslationProvider {
    var apiKey: String

    var cacheIdentifier: String { "deepl" }
    var maxBatchCharacters: Int { apiKey.isEmpty ? 1500 : 20_000 }

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        if apiKey.isEmpty {
            return try await translateWeb(texts, from: source, to: target)
        }
        return try await translateAPI(texts, from: source, to: target)
    }

    // MARK: 官方 API

    private struct APIRequest: Encodable {
        let text: [String]
        let target_lang: String
        let source_lang: String?
    }

    private struct APIResponse: Decodable {
        struct Item: Decodable { let text: String }
        let translations: [Item]
    }

    private func translateAPI(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let host = apiKey.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
        let data = try await HTTP.postJSON(
            URL(string: host + "/v2/translate")!,
            headers: ["Authorization": "DeepL-Auth-Key \(apiKey)"],
            body: APIRequest(text: texts, target_lang: Self.apiTarget(target), source_lang: source.map(Self.baseCode))
        )
        let results = try JSONDecoder().decode(APIResponse.self, from: data).translations.map(\.text)
        guard results.count == texts.count else {
            throw TranslationError.countMismatch(expected: texts.count, got: results.count)
        }
        return results
    }

    private static func apiTarget(_ language: TranslationLanguage) -> String {
        switch language.code {
        case "zh-CN": "ZH-HANS"
        case "zh-TW", "zh-HK": "ZH-HANT"
        case "en": "EN-US"
        case "pt": "PT-BR"
        default: language.code.uppercased()
        }
    }

    private static func baseCode(_ language: TranslationLanguage) -> String {
        switch language.code {
        case let code where code.hasPrefix("zh"): "ZH"
        case "no": "NB"
        default: language.code.uppercased()
        }
    }

    // MARK: 網頁版

    private func translateWeb(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let id = Int.random(in: 100_000...199_999) * 1000
        // 網頁版要求時間戳記依原文中字母 i 的數量對齊，否則判定為機器請求
        var iCount = texts.reduce(0) { $0 + $1.filter { $0 == "i" }.count }
        var timestamp = Int(Date().timeIntervalSince1970 * 1000)
        if iCount > 0 {
            iCount += 1
            timestamp = timestamp - timestamp % iCount + iCount
        }
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "LMT_handle_texts",
            "id": id,
            "params": [
                "texts": texts.map { ["text": $0, "requestAlternatives": 0] },
                "splitting": "newlines",
                "lang": [
                    "source_lang_user_selected": source.map(Self.baseCode) ?? "auto",
                    "target_lang": Self.baseCode(target),
                ],
                "timestamp": timestamp,
                "commonJobParams": ["wasSpoken": false, "transcribe_as": ""],
            ] as [String: Any],
        ]
        var json = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        // 與官方網頁相同的 "method" 空白格式
        json = json.replacingOccurrences(of: "\"method\":\"", with: (id + 5) % 29 == 0 || (id + 3) % 13 == 0 ? "\"method\" : \"" : "\"method\": \"")

        var request = URLRequest(url: URL(string: "https://www2.deepl.com/jsonrpc")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.deepl.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.deepl.com/", forHTTPHeaderField: "Referer")
        request.httpBody = Data(json.utf8)

        let (data, response) = try await WebTranslation.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 429 || (object?["error"] as? [String: Any]) != nil {
            throw TranslationError.server(429, String(localized: "DeepL 網頁版暫時限流，請稍後再試，或填入免費的 DeepL API 金鑰"))
        }
        guard let result = object?["result"] as? [String: Any], let items = result["texts"] as? [[String: Any]] else {
            throw TranslationError.malformedResponse("DeepL")
        }
        let results = items.compactMap { $0["text"] as? String }
        guard results.count == texts.count else {
            throw TranslationError.countMismatch(expected: texts.count, got: results.count)
        }
        return results.map { WebTranslation.adaptChinese($0, to: target) }
    }
}
