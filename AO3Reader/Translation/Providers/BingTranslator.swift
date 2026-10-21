// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// 微軟翻譯（Bing）：
/// - `.edgeFree`：免金鑰。先用 Edge 瀏覽器內建翻譯的匿名權杖；取不到權杖或被拒時，
///   改用 bing.com/translator 網頁版介面（兩者皆非官方介面，可能變更）
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
        switch auth {
        case .azure(let key, let region):
            var headers = ["Ocp-Apim-Subscription-Key": key]
            if !region.isEmpty { headers["Ocp-Apim-Subscription-Region"] = region }
            let request = try Self.apiRequest("https://api.cognitive.microsofttranslator.com", texts, source, target, headers)
            return try Self.decode(await HTTP.send(request), count: texts.count)
        case .edgeFree:
            do {
                let token = try await EdgeTokenStore.shared.token()
                let request = try Self.apiRequest("https://api-edge.cognitive.microsofttranslator.com", texts, source, target,
                                                  ["Authorization": "Bearer \(token)"])
                let (data, response) = try await WebTranslation.session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 { await EdgeTokenStore.shared.invalidate() }
                guard (200..<300).contains(status) else {
                    throw TranslationError.server(status, String(decoding: data.prefix(200), as: UTF8.self))
                }
                return try Self.decode(data, count: texts.count)
            } catch {
                // Edge 端點在部分地區或網路下無法使用，改走 bing.com 網頁版
                return try await BingWebSession.shared.translate(texts, from: source, to: target)
            }
        }
    }

    private static func apiRequest(_ host: String, _ texts: [String], _ source: TranslationLanguage?, _ target: TranslationLanguage,
                                   _ headers: [String: String]) throws -> URLRequest {
        var components = URLComponents(string: host + "/translate")!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: microsoftCode(target.code)),
        ]
        if let source {
            components.queryItems?.append(URLQueryItem(name: "from", value: microsoftCode(source.code)))
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONEncoder().encode(texts.map(Item.init(Text:)))
        return request
    }

    private static func decode(_ data: Data, count: Int) throws -> [String] {
        let results = try JSONDecoder().decode([Result].self, from: data).map { $0.translations.first?.text ?? "" }
        guard results.count == count else {
            throw TranslationError.countMismatch(expected: count, got: results.count)
        }
        return results
    }

    /// 微軟以文字系統區分中文：zh-Hant / zh-Hans；其餘多數語言代碼與 BCP-47 相同。
    static func microsoftCode(_ code: String) -> String {
        switch code {
        case "zh-TW", "zh-HK": "zh-Hant"
        case "zh-CN": "zh-Hans"
        case "no": "nb"
        case "tl": "fil"
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
        var request = URLRequest(url: URL(string: "https://edge.microsoft.com/translate/auth")!)
        request.timeoutInterval = 10
        let (data, response) = try await WebTranslation.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // 權杖為 JWT（三段以 . 分隔）；其他內容視為失敗
        guard (200..<300).contains(status), value.split(separator: ".").count == 3 else {
            throw TranslationError.malformedResponse("Bing token (\(status))")
        }
        token = value
        expiry = Date().addingTimeInterval(8 * 60)
        return value
    }

    func invalidate() {
        token = nil
        expiry = .distantPast
    }
}

/// bing.com/translator 網頁版：先載入翻譯頁取得 IG、IID 與防濫用權杖，再逐段呼叫 ttranslatev3。
actor BingWebSession {
    static let shared = BingWebSession()

    private struct Credentials {
        let host: String
        let ig: String
        let iid: String
        let key: String
        let token: String
        let expiry: Date
    }

    private var credentials: Credentials?
    private var counter = 0

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        var results: [String] = []
        for text in texts {
            results.append(try await translateOne(text, from: source, to: target, retry: true))
        }
        return results
    }

    private func translateOne(_ text: String, from source: TranslationLanguage?, to target: TranslationLanguage,
                              retry: Bool) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        let credentials = try await currentCredentials()
        counter += 1
        var components = URLComponents(string: "\(credentials.host)/ttranslatev3")!
        components.queryItems = [
            URLQueryItem(name: "isVertical", value: "1"),
            URLQueryItem(name: "IG", value: credentials.ig),
            URLQueryItem(name: "IID", value: "\(credentials.iid).\(counter)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("\(credentials.host)/translator", forHTTPHeaderField: "Referer")
        request.setValue(credentials.host, forHTTPHeaderField: "Origin")
        request.httpBody = Data(FormEncoding.encode([
            ("fromLang", source.map { BingTranslator.microsoftCode($0.code) } ?? "auto-detect"),
            ("to", BingTranslator.microsoftCode(target.code)),
            ("text", text),
            ("token", credentials.token),
            ("key", credentials.key),
        ]).utf8)

        let (data, response) = try await WebTranslation.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = try? JSONSerialization.jsonObject(with: data)
        if let items = object as? [[String: Any]],
           let translations = items.first?["translations"] as? [[String: Any]],
           let translated = translations.first?["text"] as? String {
            return translated
        }
        // 權杖過期或被要求重新整理：清除後重試一次
        if retry {
            self.credentials = nil
            return try await translateOne(text, from: source, to: target, retry: false)
        }
        if let dict = object as? [String: Any], let code = dict["statusCode"] as? Int {
            throw TranslationError.server(code, String(localized: "Bing 翻譯暫時無法使用，請稍後再試"))
        }
        throw TranslationError.server(status, String(decoding: data.prefix(200), as: UTF8.self))
    }

    private func currentCredentials() async throws -> Credentials {
        if let credentials, Date() < credentials.expiry { return credentials }
        let (data, response) = try await WebTranslation.session.data(from: URL(string: "https://www.bing.com/translator")!)
        let html = String(decoding: data, as: UTF8.self)
        // 中國大陸會被轉址到 cn.bing.com，後續請求需使用同一主機
        let host = (response.url?.host).map { "https://\($0)" } ?? "https://www.bing.com"
        guard let ig = Self.capture(#"IG:"([^"]+)""#, in: html),
              let iid = Self.capture(#"data-iid="([^"]+)""#, in: html),
              let params = Self.capture(#"params_AbusePreventionHelper\s*=\s*\[([^\]]+)\]"#, in: html)
        else {
            throw TranslationError.malformedResponse("Bing translator page")
        }
        let parts = params.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        guard parts.count >= 2 else { throw TranslationError.malformedResponse("Bing token") }
        let lifetime = parts.count >= 3 ? (Double(parts[2]) ?? 3_600_000) / 1000 : 3600
        let credentials = Credentials(host: host, ig: ig, iid: iid, key: parts[0], token: parts[1],
                                      expiry: Date().addingTimeInterval(min(lifetime, 3600) - 60))
        self.credentials = credentials
        counter = 0
        return credentials
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
