// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Google 網頁翻譯端點（免金鑰）。非官方公開 API，可能被限流，適合作為預設的開箱即用選項。
struct GoogleWebTranslator: TranslationProvider {
    var cacheIdentifier: String { "google-web" }
    var maxBatchCharacters: Int { 4000 }

    /// 同時進行的請求數，過高容易觸發 429
    private let concurrency = 4

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        var results = Array(repeating: "", count: texts.count)
        for chunkStart in stride(from: 0, to: texts.count, by: concurrency) {
            let range = chunkStart..<min(chunkStart + concurrency, texts.count)
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for index in range {
                    let text = texts[index]
                    group.addTask { (index, try await translateOne(text, from: source, to: target)) }
                }
                for try await (index, translated) in group {
                    results[index] = translated
                }
            }
        }
        return results
    }

    private func translateOne(_ text: String, from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source?.code ?? "auto"),
            URLQueryItem(name: "tl", value: target.code),
            URLQueryItem(name: "dt", value: "t"),
        ]
        // 長段落放在 POST body，避免 URL 過長
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(FormEncoding.encode([("q", text)]).utf8)

        let data = try await HTTP.send(request)
        // 回應格式：[[["譯文","原文",...], ["譯文","原文",...]], ...]
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [Any]
        else { throw TranslationError.malformedResponse("Google") }
        return sentences.compactMap { ($0 as? [Any])?.first as? String }.joined()
    }
}

/// Google Cloud Translation v2（需 API Key，支援批次）。
struct GoogleCloudTranslator: TranslationProvider {
    let apiKey: String

    var cacheIdentifier: String { "google-cloud" }
    var maxBatchCharacters: Int { 25_000 }

    private struct Request: Encodable {
        let q: [String]
        let target: String
        let source: String?
        let format = "text"
    }

    private struct Response: Decodable {
        struct Payload: Decodable { let translations: [Item] }
        struct Item: Decodable { let translatedText: String }
        let data: Payload
    }

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let url = URL(string: "https://translation.googleapis.com/language/translate/v2")!
        let data = try await HTTP.postJSON(url, headers: ["X-Goog-Api-Key": apiKey], body: Request(q: texts, target: target.code, source: source?.code))
        let translations = try JSONDecoder().decode(Response.self, from: data).data.translations.map(\.translatedText)
        guard translations.count == texts.count else {
            throw TranslationError.countMismatch(expected: texts.count, got: translations.count)
        }
        return translations
    }
}
