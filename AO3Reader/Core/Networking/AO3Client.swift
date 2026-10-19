import Foundation

enum AO3Error: LocalizedError, Equatable {
    case http(Int)
    case rateLimited(retryAfter: String?)
    case cloudflareChallenge
    case requiresLogin
    case loginFailed
    case parse(String)
    case invalidSource

    var errorDescription: String? {
        switch self {
        case .http(let code): "伺服器回應錯誤（HTTP \(code)）"
        case .rateLimited(let after): "請求過於頻繁，AO3 暫時限制存取" + (after.map { "，請於 \($0) 秒後再試" } ?? "")
        case .cloudflareChallenge: "來源要求瀏覽器驗證，請改用「網頁登入」通過驗證後再試"
        case .requiresLogin: "此作品僅限登入用戶閱讀"
        case .loginFailed: "登入失敗，請檢查帳號密碼"
        case .parse(let what): "頁面解析失敗：\(what)"
        case .invalidSource: "無效的來源網址"
        }
    }
}

/// 對某個 AO3 來源（官網或鏡像）的 HTML 存取。
/// 所有請求共用 `HTTPCookieStorage.shared`，因此登入狀態以「來源網域」為單位保存。
struct AO3Client: Sendable {
    let baseURL: URL

    /// 與網頁登入（WKWebView）使用同一個 UA，避免 Cloudflare clearance cookie 失效。
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "text/html,application/xhtml+xml",
        ]
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    // MARK: - Raw requests

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> String {
        try await send(URLRequest(url: url(path, query: query)))
    }

    func postForm(_ path: String, fields: [(String, String)]) async throws -> (String, HTTPURLResponse) {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(url(path).absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data(FormEncoding.encode(fields).utf8)
        let (data, response) = try await Self.session.data(for: request)
        let http = response as! HTTPURLResponse
        try Self.validate(http)
        return (String(decoding: data, as: UTF8.self), http)
    }

    private func send(_ request: URLRequest) async throws -> String {
        let (data, response) = try await Self.session.data(for: request)
        try Self.validate(response as! HTTPURLResponse)
        return String(decoding: data, as: UTF8.self)
    }

    private static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<400: return
        case 429: throw AO3Error.rateLimited(retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        case 403 where response.value(forHTTPHeaderField: "cf-mitigated") != nil
                    || response.value(forHTTPHeaderField: "Server")?.lowercased() == "cloudflare":
            throw AO3Error.cloudflareChallenge
        default: throw AO3Error.http(response.statusCode)
        }
    }

    // MARK: - High level API

    func searchWorks(_ query: WorkSearchQuery, page: Int = 1) async throws -> WorkPage {
        let html = try await get("/works/search", query: query.queryItems(page: page))
        return try AO3Parser.workPage(html: html, page: page)
    }

    func work(id: Int) async throws -> WorkDetail {
        let html = try await get("/works/\(id)", query: [
            URLQueryItem(name: "view_full_work", value: "true"),
            URLQueryItem(name: "view_adult", value: "true"),
        ])
        return try AO3Parser.workDetail(html: html, id: id)
    }

    func userList(_ kind: UserListKind, username: String, page: Int = 1) async throws -> WorkPage {
        var (path, query) = kind.path(username: username)
        if page > 1 { query.append(URLQueryItem(name: "page", value: String(page))) }
        let html = try await get(path, query: query)
        return try AO3Parser.workPage(html: html, page: page)
    }

    /// 以首頁判斷來源是否為可用的 AO3（或其鏡像），並回傳目前登入的用戶名。
    func probe() async throws -> (isAO3: Bool, username: String?) {
        let html = try await get("/")
        return (AO3Parser.looksLikeAO3(html), AO3Parser.loggedInUsername(html))
    }
}

enum FormEncoding {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._*")
        return set
    }()

    static func encode(_ fields: [(String, String)]) -> String {
        fields.map { key, value in
            "\(escape(key))=\(escape(value))"
        }.joined(separator: "&")
    }

    static func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
