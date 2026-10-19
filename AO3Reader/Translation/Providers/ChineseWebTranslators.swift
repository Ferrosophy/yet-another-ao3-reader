import Foundation

// 免金鑰的中文網頁翻譯服務。皆為非官方介面（與網頁版或瀏覽器擴充所用相同），
// 網站改版或觸發風控時可能失效；需要驗證時會拋出 verificationRequired，由介面彈出網頁驗證視窗。

/// 騰訊交互翻譯 TranSmart：支援批次，原文語言需指定（未指定時在本機偵測）。
struct TransmartTranslator: TranslationProvider {
    var cacheIdentifier: String { "transmart" }
    var maxBatchCharacters: Int { 5000 }

    private static let endpoint = URL(string: "https://transmart.qq.com/api/imt")!
    private static let site = URL(string: "https://transmart.qq.com/")!

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let source = source ?? WebTranslation.detect(texts) ?? .named("en")
        let millis = Int(Date().timeIntervalSince1970 * 1000)
        let body: [String: Any] = [
            "header": [
                "fn": "auto_translation",
                "client_key": "browser-chrome-120.0.0-Mac OS-\(UUID().uuidString.lowercased())-\(millis)",
            ],
            "type": "plain",
            "model_category": "normal",
            "text_domain": "general",
            "source": ["lang": Self.code(source), "text_list": texts],
            "target": ["lang": Self.code(target)],
        ]
        let json = try await WebTranslation.postJSON(Self.endpoint, body: body,
                                                     headers: ["Referer": "https://transmart.qq.com/", "Origin": "https://transmart.qq.com"],
                                                     provider: "TranSmart", verifyAt: Self.site)
        guard let header = json["header"] as? [String: Any], header["ret_code"] as? String == "succ",
              let results = json["auto_translation"] as? [String]
        else {
            let message = (json["header"] as? [String: Any])?["ret_code"] as? String ?? "unknown"
            throw TranslationError.malformedResponse("TranSmart: \(message)")
        }
        guard results.count == texts.count else {
            throw TranslationError.countMismatch(expected: texts.count, got: results.count)
        }
        return results.map { WebTranslation.adaptChinese($0, to: target) }
    }

    /// 中文一律要求簡體，繁體目標在本機轉換
    private static func code(_ language: TranslationLanguage) -> String {
        WebTranslation.isChinese(language) ? "zh" : language.code
    }
}

/// 火山翻譯（字節跳動）：瀏覽器擴充使用的端點，每段一個請求。
struct VolcanoTranslator: TranslationProvider {
    var cacheIdentifier: String { "volcano" }
    var maxBatchCharacters: Int { 3000 }

    private static let endpoint = URL(string: "https://translate.volcengine.com/crx/translate/v1/")!
    private static let site = URL(string: "https://translate.volcengine.com/")!

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let sourceCode = source.map(Self.code) ?? "detect"
        let targetCode = Self.code(target)
        return try await WebTranslation.mapConcurrently(texts) { text in
            let json = try await WebTranslation.postJSON(Self.endpoint, body: [
                "source_language": sourceCode,
                "target_language": targetCode,
                "text": text,
            ], provider: String(localized: "火山翻譯"), verifyAt: Self.site)
            guard let translation = json["translation"] as? String else {
                throw TranslationError.malformedResponse("Volcano: \(json["base_resp"] ?? json)")
            }
            return WebTranslation.adaptChinese(translation, to: target)
        }
    }

    private static func code(_ language: TranslationLanguage) -> String {
        WebTranslation.isChinese(language) ? "zh" : language.code
    }
}

/// 百度翻譯網頁版（transapi 端點），每段一個請求。
struct BaiduWebTranslator: TranslationProvider {
    var cacheIdentifier: String { "baidu-web" }
    var maxBatchCharacters: Int { 3000 }

    private static let endpoint = URL(string: "https://fanyi.baidu.com/transapi")!
    private static let site = URL(string: "https://fanyi.baidu.com/")!

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let from = source.map(Self.code) ?? "auto"
        let to = Self.code(target)
        let provider = String(localized: "百度翻譯")
        return try await WebTranslation.mapConcurrently(texts) { text in
            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("https://fanyi.baidu.com/", forHTTPHeaderField: "Referer")
            request.httpBody = Data(FormEncoding.encode([("from", from), ("to", to), ("query", text), ("source", "txt")]).utf8)
            let data = try await WebTranslation.send(request, provider: provider, verifyAt: Self.site)
            let json = try WebTranslation.json(data, provider: provider, verifyAt: Self.site)
            guard let items = json["data"] as? [[String: Any]] else {
                // status 非 0 多為風控，交給使用者到網頁版完成驗證
                throw WebTranslation.challengeError(provider, Self.site)
            }
            let joined = items.compactMap { $0["dst"] as? String }.joined(separator: "\n")
            return WebTranslation.adaptChinese(joined, to: target)
        }
    }

    private static func code(_ language: TranslationLanguage) -> String {
        switch language.code {
        case "zh-CN", "zh-TW", "zh-HK": "zh"
        case "ja": "jp"
        case "ko": "kor"
        case "fr": "fra"
        case "es": "spa"
        case "vi": "vie"
        case "ar": "ara"
        case "uk": "ukr"
        default: language.code
        }
    }
}

/// 有道翻譯網頁版（舊版公開端點），只支援譯成中文或英文。
struct YoudaoWebTranslator: TranslationProvider {
    var cacheIdentifier: String { "youdao-web" }
    var maxBatchCharacters: Int { 3000 }

    private static let site = URL(string: "https://fanyi.youdao.com/")!

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let type: String
        if WebTranslation.isChinese(target) {
            type = source.flatMap(Self.code).map { "\($0)2ZH_CN" } ?? "AUTO"
        } else if target.code == "en" {
            type = "ZH_CN2EN"
        } else {
            throw TranslationError.unsupportedLanguage(String(localized: "有道翻譯（網頁版）只支援譯成中文或英文"))
        }
        let provider = String(localized: "有道翻譯")
        return try await WebTranslation.mapConcurrently(texts) { text in
            var components = URLComponents(string: "https://fanyi.youdao.com/translate")!
            components.queryItems = [
                URLQueryItem(name: "doctype", value: "json"),
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "i", value: text),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("https://fanyi.youdao.com/", forHTTPHeaderField: "Referer")
            let data = try await WebTranslation.send(request, provider: provider, verifyAt: Self.site)
            let json = try WebTranslation.json(data, provider: provider, verifyAt: Self.site)
            guard (json["errorCode"] as? Int) == 0, let groups = json["translateResult"] as? [[[String: Any]]] else {
                throw TranslationError.malformedResponse("Youdao: errorCode \(json["errorCode"] ?? "?")")
            }
            // 外層每個陣列是一行，內層是該行的句子
            let lines = groups.map { line in line.compactMap { $0["tgt"] as? String }.joined() }
            return WebTranslation.adaptChinese(lines.joined(separator: "\n"), to: target)
        }
    }

    private static func code(_ language: TranslationLanguage) -> String? {
        switch language.code {
        case "en": "EN"
        case "ja": "JA"
        case "ko": "KR"
        case "fr": "FR"
        case "ru": "RU"
        case "es": "SP"
        default: nil
        }
    }
}

/// 搜狗翻譯網頁版：需要先取得網站 Cookie，請求以 MD5 簽章。
struct SogouWebTranslator: TranslationProvider {
    var cacheIdentifier: String { "sogou-web" }
    var maxBatchCharacters: Int { 3000 }

    private static let endpoint = URL(string: "https://fanyi.sogou.com/api/transpc/text/result")!
    private static let site = URL(string: "https://fanyi.sogou.com/text")!
    /// 網頁版腳本中的固定簽章鹽值
    private static let secret = "109984457"

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let provider = String(localized: "搜狗翻譯")
        // 先造訪網頁取得 SNUID 等 Cookie，否則 API 會拒絕請求
        if (HTTPCookieStorage.shared.cookies(for: Self.site) ?? []).isEmpty {
            _ = try? await WebTranslation.send(URLRequest(url: Self.site), provider: provider, verifyAt: Self.site)
        }
        let from = source.map(Self.code) ?? "auto"
        let to = Self.code(target)
        return try await WebTranslation.mapConcurrently(texts, limit: 2) { text in
            let json = try await WebTranslation.postJSON(Self.endpoint, body: [
                "from": from,
                "to": to,
                "text": text,
                "client": "pc",
                "fr": "browser_pc",
                "needQc": 1,
                "s": WebTranslation.md5("\(from)\(to)\(text)\(Self.secret)"),
                "uuid": UUID().uuidString.lowercased(),
                "exchange": false,
            ], headers: ["Referer": Self.site.absoluteString, "Origin": "https://fanyi.sogou.com"],
               provider: provider, verifyAt: Self.site)
            guard let data = json["data"] as? [String: Any],
                  let translate = data["translate"] as? [String: Any],
                  let result = translate["dit"] as? String
            else {
                throw WebTranslation.challengeError(provider, Self.site)
            }
            return WebTranslation.adaptChinese(result, to: target)
        }
    }

    private static func code(_ language: TranslationLanguage) -> String {
        WebTranslation.isChinese(language) ? "zh-CHS" : language.code
    }
}
