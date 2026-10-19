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

    /// 從官網搜尋表單讀取所有可篩選的語言。
    func languages() async throws -> [AO3Language] {
        try AO3Parser.languageOptions(html: try await get("/works/search"))
    }

    /// 任意作品列表頁（標籤、合集、系列、用戶作品…），列表中的 `li.blurb` 皆可解析。
    func worksPage(path: String, query: [URLQueryItem] = [], page: Int = 1) async throws -> WorkPage {
        let html = try await get(path, query: Self.paged(query, page))
        return try AO3Parser.workPage(html: html, page: page)
    }

    func searchTags(name: String, type: TagSearchType, page: Int = 1) async throws -> ListPage<TagResult> {
        let html = try await get("/tags/search", query: Self.paged([
            URLQueryItem(name: "tag_search[name]", value: name),
            URLQueryItem(name: "tag_search[type]", value: type.rawValue),
            URLQueryItem(name: "tag_search[sort_column]", value: "uses"),
            URLQueryItem(name: "tag_search[sort_direction]", value: "desc"),
            URLQueryItem(name: "commit", value: "Search Tags"),
        ], page))
        return try AO3Parser.tagResults(html: html, page: page)
    }

    func searchPeople(name: String, page: Int = 1) async throws -> ListPage<PersonResult> {
        let html = try await get("/people/search", query: Self.paged([
            URLQueryItem(name: "people_search[name]", value: name),
            URLQueryItem(name: "commit", value: "Search People"),
        ], page))
        return try AO3Parser.peopleResults(html: html, page: page)
    }

    func searchCollections(title: String, page: Int = 1) async throws -> ListPage<CollectionResult> {
        var query: [URLQueryItem] = []
        if !title.isEmpty {
            query = [
                URLQueryItem(name: "collection_search[title]", value: title),
                URLQueryItem(name: "commit", value: "Sort and Filter"),
            ]
        }
        let html = try await get("/collections", query: Self.paged(query, page))
        return try AO3Parser.collectionResults(html: html, page: page)
    }

    func subscriptions(username: String, kind: SubscriptionItem.Kind, page: Int = 1) async throws -> ListPage<SubscriptionItem> {
        let html = try await get("/users/\(username)/subscriptions", query: Self.paged([
            URLQueryItem(name: "type", value: kind.rawValue),
        ], page))
        return try AO3Parser.subscriptions(html: html, page: page)
    }

    func inbox(username: String, unreadOnly: Bool, page: Int = 1) async throws -> ListPage<InboxComment> {
        var query: [URLQueryItem] = []
        if unreadOnly { query.append(URLQueryItem(name: "filters[read]", value: "false")) }
        let html = try await get("/users/\(username)/inbox", query: Self.paged(query, page))
        return try AO3Parser.inbox(html: html, page: page)
    }

    /// AO3 輸入框自動完成（/autocomplete/fandom 等），回傳 `[{id, name}]`。
    func autocomplete(_ kind: AutocompleteKind, term: String) async throws -> [String] {
        var request = URLRequest(url: url("/autocomplete/\(kind.rawValue)", query: [URLQueryItem(name: "term", value: term)]))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await Self.session.data(for: request)
        if let http = response as? HTTPURLResponse { try Self.validate(http) }
        struct Item: Decodable { let name: String }
        return try JSONDecoder().decode([Item].self, from: data).map(\.name)
    }

    private static func paged(_ query: [URLQueryItem], _ page: Int) -> [URLQueryItem] {
        page > 1 ? query + [URLQueryItem(name: "page", value: String(page))] : query
    }

    /// 以首頁判斷來源是否為可用的 AO3（或其鏡像），並回傳目前登入的用戶名。
    func probe() async throws -> (isAO3: Bool, username: String?) {
        let html = try await get("/")
        return (AO3Parser.looksLikeAO3(html), AO3Parser.loggedInUsername(html))
    }
}

/// Tag Search 的類型篩選，值與官網 radio button 相同。
enum TagSearchType: String, CaseIterable, Identifiable, Sendable {
    case any = "", fandom = "Fandom", character = "Character", relationship = "Relationship", freeform = "Freeform"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: "全部類型"
        case .fandom: "Fandom"
        case .character: "角色"
        case .relationship: "配對"
        case .freeform: "其他標籤"
        }
    }
}

/// /autocomplete/<kind> 端點。
enum AutocompleteKind: String, Sendable {
    case tag, fandom, character, relationship, freeform
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
