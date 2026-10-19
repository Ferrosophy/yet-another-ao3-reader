import CryptoKit
import Foundation
import NaturalLanguage

/// 翻譯時需要使用者介入的情況：網頁驗證（驗證碼 / 安全檢查）或 Apple 翻譯需下載語言。
enum TranslationChallenge: Identifiable, Hashable, Sendable {
    case web(provider: String, url: URL)
    case appleDownload(source: String, target: String)

    var id: String {
        switch self {
        case .web(_, let url): "web:\(url.absoluteString)"
        case .appleDownload(let source, let target): "apple:\(source)>\(target)"
        }
    }
}

/// 模擬瀏覽器的免金鑰網頁翻譯（騰訊、火山、百度、有道、搜狗、DeepL 網頁版）共用工具。
/// 這些都是非官方介面，網站改版或觸發風控時可能失效；遇到驗證時改由使用者在網頁視窗完成。
enum WebTranslation {
    /// 與網頁驗證視窗共用 Cookie（HTTPCookieStorage 依網域隔離，不會把 AO3 Cookie 送給翻譯網站）
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": AO3Client.userAgent]
        return URLSession(configuration: config)
    }()

    /// 送出請求；被要求驗證（403、驗證碼頁面）時拋出 `verificationRequired`。
    static func send(_ request: URLRequest, provider: String, verifyAt url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || looksLikeChallenge(data) {
            throw TranslationError.verificationRequired(.web(provider: provider, url: url))
        }
        guard (200..<300).contains(status) else {
            throw TranslationError.server(status, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    static func challengeError(_ provider: String, _ url: URL) -> TranslationError {
        .verificationRequired(.web(provider: provider, url: url))
    }

    /// 回應是 HTML 而非 JSON，且含驗證碼相關字樣
    private static func looksLikeChallenge(_ data: Data) -> Bool {
        guard data.first == UInt8(ascii: "<") else { return false }
        let head = String(decoding: data.prefix(4000), as: UTF8.self).lowercased()
        return ["captcha", "验证", "驗證", "安全验证", "antispider"].contains { head.contains($0) }
    }

    static func postJSON(_ url: URL, body: [String: Any], headers: [String: String] = [:],
                         provider: String, verifyAt: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try json(await send(request, provider: provider, verifyAt: verifyAt), provider: provider, verifyAt: verifyAt)
    }

    static func json(_ data: Data, provider: String, verifyAt: URL) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 非 JSON 多半是被導向驗證或錯誤頁
            throw challengeError(provider, verifyAt)
        }
        return object
    }

    static func md5(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 只輸出簡體中文的服務，目標為繁體時在本機轉換
    static func adaptChinese(_ text: String, to target: TranslationLanguage) -> String {
        guard target.code == "zh-TW" || target.code == "zh-HK" else { return text }
        return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    static func isChinese(_ language: TranslationLanguage) -> Bool { language.code.hasPrefix("zh") }

    /// 不支援自動偵測的服務，用 NaturalLanguage 在本機判斷原文語言
    static func detect(_ texts: [String]) -> TranslationLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(texts.joined(separator: "\n").prefix(2000).description)
        guard let language = recognizer.dominantLanguage else { return nil }
        let code: String = switch language {
        case .simplifiedChinese: "zh-CN"
        case .traditionalChinese: "zh-TW"
        default: language.rawValue
        }
        return TranslationLanguage.all.first { $0.code == code }
    }

    /// 每段一個請求的服務：限制同時請求數，保持結果順序
    static func mapConcurrently(_ texts: [String], limit: Int = 3,
                                _ operation: @escaping @Sendable (String) async throws -> String) async throws -> [String] {
        var results = Array(repeating: "", count: texts.count)
        for start in stride(from: 0, to: texts.count, by: limit) {
            let range = start..<min(start + limit, texts.count)
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for index in range {
                    let text = texts[index]
                    group.addTask { (index, try await operation(text)) }
                }
                for try await (index, value) in group { results[index] = value }
            }
        }
        return results
    }
}
