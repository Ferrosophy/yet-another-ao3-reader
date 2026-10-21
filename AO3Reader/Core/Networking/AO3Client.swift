import Foundation

enum AO3Error: LocalizedError, Equatable {
    case http(Int)
    case rateLimited(retryAfter: String?)
    case cloudflareChallenge
    /// 鏡像站的 Anubis 反爬蟲驗證（工作量證明，需在瀏覽器中執行）
    case anubisChallenge
    case requiresLogin
    case loginFailed
    case parse(String)
    case invalidSource
    /// AO3 頁面上的提示訊息（例如 Kudos 被拒絕的原因）
    case message(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): String(localized: "伺服器回應錯誤（HTTP \(code)）")
        case .rateLimited(let after): after.map { String(localized: "請求過於頻繁，AO3 暫時限制存取，請於 \($0) 秒後再試") } ?? String(localized: "請求過於頻繁，AO3 暫時限制存取")
        case .cloudflareChallenge: String(localized: "網站要求人機驗證（Cloudflare），請在彈出的頁面完成驗證後重試")
        case .anubisChallenge: String(localized: "鏡像站要求瀏覽器驗證（Anubis），請在彈出的頁面等待驗證完成後重試")
        case .requiresLogin: String(localized: "此作品僅限登入用戶閱讀")
        case .loginFailed: String(localized: "登入失敗，請檢查帳號密碼")
        case .parse(let what): String(localized: "頁面解析失敗：\(what)")
        case .invalidSource: String(localized: "無效的來源網址")
        case .message(let text): text
        }
    }
}

extension Notification.Name {
    /// AO3 請求遇到 Cloudflare 人機驗證；userInfo["url"] 為觸發驗證的網址
    static let ao3CloudflareChallenge = Notification.Name("AO3CloudflareChallenge")
}

/// 對某個 AO3 來源（官網或鏡像）的 HTML 存取。
/// 所有請求共用 `HTTPCookieStorage.shared`，因此登入狀態以「來源網域」為單位保存。
struct AO3Client: Sendable {
    let baseURL: URL

    /// 與網頁登入（WKWebView）使用同一個 UA，避免 Cloudflare clearance cookie 失效。
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    static let session = makeSession(timeout: 30)
    /// 下載整部作品用：長篇作品的完整內容頁 AO3 可能要很久才開始回應
    static let longSession = makeSession(timeout: 180)

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "text/html,application/xhtml+xml",
            // 與網頁驗證（WKWebView）使用相同格式的語言標頭：Anubis 等防護會比對請求標頭
            "Accept-Language": acceptLanguage,
        ]
        config.timeoutIntervalForRequest = timeout
        return URLSession(configuration: config)
    }

    /// 仿照 Safari 的 Accept-Language（例如 zh-CN,zh-Hans;q=0.9 或 en-US,en;q=0.9）
    static let acceptLanguage: String = {
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        let locale = Locale(identifier: preferred)
        let language = locale.language.languageCode?.identifier ?? "en"
        let region = locale.region?.identifier
        let script = locale.language.script?.identifier
        let primary = region.map { "\(language)-\($0)" } ?? language
        let secondary = script.map { "\(language)-\($0)" } ?? language
        return primary == secondary ? primary : "\(primary),\(secondary);q=0.9"
    }()

    /// 除錯紀錄中顯示的請求標頭
    static func requestHeaders(_ request: URLRequest, session: URLSession) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in session.configuration.httpAdditionalHeaders ?? [:] { headers["\(key)"] = "\(value)" }
        for (key, value) in request.allHTTPHeaderFields ?? [:] { headers[key] = value }
        return headers
    }

    /// 展示模式的來源：內容由 `DemoSite` 提供，不送出任何網路請求
    var isDemo: Bool { baseURL.host() == DemoSite.host }

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    // MARK: - Raw requests

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> String {
        try await send(URLRequest(url: url(path, query: query)))
    }

    func postForm(_ path: String, fields: [(String, String)], referer: String? = nil) async throws -> (String, HTTPURLResponse) {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(referer ?? url(path).absoluteString, forHTTPHeaderField: "Referer")
        if let token = fields.first(where: { $0.0 == "authenticity_token" })?.1 {
            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
        }
        request.httpBody = Data(FormEncoding.encode(fields).utf8)
        let (data, response) = try await load(request, session: Self.session)
        let http = response as! HTTPURLResponse
        try validate(http, data: data, request: request, session: Self.session)
        return (String(decoding: data, as: UTF8.self), http)
    }

    private func send(_ request: URLRequest, session: URLSession = AO3Client.session) async throws -> String {
        let (data, response) = try await load(request, session: session)
        try validate(response as! HTTPURLResponse, data: data, request: request, session: session)
        return String(decoding: data, as: UTF8.self)
    }

    /// 送出請求；網路錯誤記入除錯紀錄
    private func load(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            DebugLog.record(DebugEntry(kind: .network, method: request.httpMethod ?? "GET", url: request.url?.absoluteString ?? "",
                                       summary: error.localizedDescription,
                                       detail: Self.requestHeaders(request, session: session).sorted { $0.key < $1.key }
                                           .map { "\($0.key): \($0.value)" }.joined(separator: "\n")))
            throw error
        }
    }

    private func validate(_ response: HTTPURLResponse, data: Data, request: URLRequest, session: URLSession) throws {
        let method = request.httpMethod ?? "GET"
        let headers = Self.requestHeaders(request, session: session)
        func log(_ kind: DebugEntry.Kind, _ summary: String) {
            DebugLog.record(.response(response, data: data, method: method, requestHeaders: headers, kind: kind, summary: summary))
        }
        if Self.isCloudflareChallenge(response, data: data) {
            log(.cloudflare, "Cloudflare challenge")
            // 通知介面彈出驗證頁，讓使用者點一下人機驗證
            NotificationCenter.default.post(name: .ao3CloudflareChallenge, object: nil,
                                            userInfo: ["url": response.url ?? baseURL])
            throw AO3Error.cloudflareChallenge
        }
        if Self.isAnubisChallenge(data: data) {
            log(.anubis, "Anubis challenge")
            // Anubis 需要在瀏覽器中計算工作量證明，同樣以驗證頁處理
            NotificationCenter.default.post(name: .ao3CloudflareChallenge, object: nil,
                                            userInfo: ["url": response.url ?? baseURL])
            throw AO3Error.anubisChallenge
        }
        switch response.statusCode {
        case 200..<400:
            log(.ok, "OK (\(data.count) bytes)")
        case 429:
            log(.http, "Rate limited")
            throw AO3Error.rateLimited(retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        default:
            log(.http, "HTTP \(response.statusCode)")
            throw AO3Error.http(response.statusCode)
        }
    }

    /// 人機驗證後確認 App 的網路層也能取得頁面（不記為一般請求、不彈出驗證頁）。
    /// 網頁通過但這裡仍被攔下，表示驗證 Cookie 沒有在 App 的請求中生效。
    static func verifyAccess(_ url: URL) async -> Bool {
        let request = URLRequest(url: url)
        let headers = requestHeaders(request, session: session)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let ok = !isCloudflareChallenge(http, data: data) && !isAnubisChallenge(data: data) && http.statusCode < 400
            DebugLog.record(.response(http, data: data, method: "GET", requestHeaders: headers, kind: .verify,
                                      summary: ok ? "App request after verification: OK" : "App request after verification: still blocked (HTTP \(http.statusCode))"))
            return ok
        } catch {
            DebugLog.record(DebugEntry(kind: .verify, url: url.absoluteString, summary: "App request after verification failed: \(error.localizedDescription)"))
            return false
        }
    }

    /// Anubis（TecharoHQ/anubis）的驗證頁：含 Anubis 的腳本或路徑
    static func isAnubisChallenge(data: Data) -> Bool {
        let head = String(decoding: data.prefix(16_000), as: UTF8.self)
        return head.contains("anubis_challenge") || head.contains("/.within.website/")
            || (head.localizedCaseInsensitiveContains("anubis") && head.contains("Making sure you"))
    }

    /// 頁面解析失敗時記入除錯紀錄（例如鏡像回傳了非 AO3 的頁面）
    private func parsed<T>(_ path: String, _ html: String, _ parse: () throws -> T) throws -> T {
        do {
            return try parse()
        } catch {
            DebugLog.record(DebugEntry(kind: .parse, url: baseURL.appending(path: path).absoluteString,
                                       summary: error.localizedDescription,
                                       detail: "— Body (first 1500 chars) —\n" + String(html.prefix(1500))))
            throw error
        }
    }

    /// Cloudflare 的人機驗證頁：回應標頭 cf-mitigated: challenge，或 403 / 503 的「Just a moment...」頁面。
    static func isCloudflareChallenge(_ response: HTTPURLResponse, data: Data) -> Bool {
        if response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" { return true }
        let head = String(decoding: data.prefix(16_000), as: UTF8.self)
        if [403, 503].contains(response.statusCode) {
            return head.contains("<title>Just a moment") || head.contains("cf_chl_opt") || head.contains("cf-turnstile")
        }
        // 一般頁面也可能被注入 challenge-platform 腳本，所以 200 回應只認完整的驗證頁
        return head.contains("<title>Just a moment") && head.contains("cf_chl_opt")
    }

    // MARK: - High level API

    func searchWorks(_ query: WorkSearchQuery, page: Int = 1) async throws -> WorkPage {
        if isDemo { return DemoSite.searchPage(query, page: page) }
        let html = try await get("/works/search", query: query.queryItems(page: page))
        return try parsed("/works/search", html) { try AO3Parser.workPage(html: html, page: page) }
    }

    func work(id: Int) async throws -> WorkDetail {
        if isDemo { return try DemoSite.detail(id: id) }
        var request = URLRequest(url: url("/works/\(id)", query: [
            URLQueryItem(name: "view_full_work", value: "true"),
            URLQueryItem(name: "view_adult", value: "true"),
        ]))
        // 長篇作品的完整內容頁 AO3 可能要很久才開始回應，放寬逾時（一般頁面為 30 秒）
        request.timeoutInterval = 180
        let html = try await send(request, session: Self.longSession)
        return try parsed("/works/\(id)", html) { try AO3Parser.workDetail(html: html, id: id) }
    }

    /// 作品的評論（整部作品，每則標示所屬章節）；`show_comments` 讓官網直接輸出評論區。
    func comments(workID: Int, page: Int = 1) async throws -> CommentPage {
        if isDemo { return DemoSite.comments(workID: workID, page: page) }
        var query = [
            URLQueryItem(name: "show_comments", value: "true"),
            URLQueryItem(name: "view_full_work", value: "true"),
            URLQueryItem(name: "view_adult", value: "true"),
        ]
        if page > 1 { query.append(URLQueryItem(name: "page", value: String(page))) }
        var request = URLRequest(url: url("/works/\(workID)", query: query))
        // 與完整作品頁相同：長篇作品的頁面可能要很久才開始回應
        request.timeoutInterval = 180
        let html = try await send(request, session: Self.longSession)
        return try parsed("/works/\(workID)", html) { try AO3Parser.comments(html: html, page: page) }
    }

    func userList(_ kind: UserListKind, username: String, page: Int = 1) async throws -> WorkPage {
        if isDemo { return WorkPage(works: [], page: page, hasNextPage: false) }
        var (path, query) = kind.path(username: username)
        if page > 1 { query.append(URLQueryItem(name: "page", value: String(page))) }
        let html = try await get(path, query: query)
        return try AO3Parser.workPage(html: html, page: page)
    }

    /// 從官網搜尋表單讀取所有可篩選的語言。
    func languages() async throws -> [AO3Language] {
        if isDemo { return DemoSite.languages }
        AO3Language.bySpeakers(try AO3Parser.languageOptions(html: try await get("/works/search")))
    }

    /// 任意作品列表頁（標籤、合集、系列、用戶作品…），列表中的 `li.blurb` 皆可解析。
    func worksPage(path: String, query: [URLQueryItem] = [], page: Int = 1) async throws -> WorkPage {
        if isDemo { return DemoSite.worksPage(path: path, page: page) }
        let html = try await get(path, query: Self.paged(query, page))
        return try parsed(path, html) { try AO3Parser.workPage(html: html, page: page) }
    }

    func searchTags(name: String, type: TagSearchType, page: Int = 1) async throws -> ListPage<TagResult> {
        if isDemo { return DemoSite.tagResults(name: name, type: type, page: page) }
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
        if isDemo { return ListPage(items: [], page: page, hasNextPage: false) }
        let html = try await get("/people/search", query: Self.paged([
            URLQueryItem(name: "people_search[name]", value: name),
            URLQueryItem(name: "commit", value: "Search People"),
        ], page))
        return try AO3Parser.peopleResults(html: html, page: page)
    }

    func searchCollections(title: String, page: Int = 1) async throws -> ListPage<CollectionResult> {
        if isDemo { return ListPage(items: [], page: page, hasNextPage: false) }
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
        if isDemo { return ListPage(items: [], page: page, hasNextPage: false) }
        let html = try await get("/users/\(username)/subscriptions", query: Self.paged([
            URLQueryItem(name: "type", value: kind.rawValue),
        ], page))
        return try AO3Parser.subscriptions(html: html, page: page)
    }

    func inbox(username: String, unreadOnly: Bool, page: Int = 1) async throws -> ListPage<InboxComment> {
        if isDemo { return ListPage(items: [], page: page, hasNextPage: false) }
        var query: [URLQueryItem] = []
        if unreadOnly { query.append(URLQueryItem(name: "filters[read]", value: "false")) }
        let html = try await get("/users/\(username)/inbox", query: Self.paged(query, page))
        return try AO3Parser.inbox(html: html, page: page)
    }

    /// AO3 輸入框自動完成（/autocomplete/fandom 等），回傳 `[{id, name}]`。
    func autocomplete(_ kind: AutocompleteKind, term: String) async throws -> [String] {
        if isDemo { return DemoSite.autocomplete(kind, term: term) }
        var request = URLRequest(url: url("/autocomplete/\(kind.rawValue)", query: [URLQueryItem(name: "term", value: term)]))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await load(request, session: Self.session)
        if let http = response as? HTTPURLResponse { try validate(http, data: data, request: request, session: Self.session) }
        struct Item: Decodable { let name: String }
        return try JSONDecoder().decode([Item].self, from: data).map(\.name)
    }

    private static func paged(_ query: [URLQueryItem], _ page: Int) -> [URLQueryItem] {
        page > 1 ? query + [URLQueryItem(name: "page", value: String(page))] : query
    }

    /// 以首頁判斷來源是否為可用的 AO3（或其鏡像），並回傳目前登入的用戶名。
    func probe() async throws -> (isAO3: Bool, username: String?) {
        if isDemo { return (true, nil) }
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
        case .any: String(localized: "全部")
        case .fandom: String(localized: "原作")
        case .character: String(localized: "角色")
        case .relationship: String(localized: "配對")
        case .freeform: String(localized: "其他")
        }
    }
}

/// /autocomplete/<kind> 端點。
enum AutocompleteKind: String, Sendable {
    case tag, fandom, character, relationship, freeform
    /// 用戶（pseud），名稱格式為「pseud (user)」
    case pseud
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

extension HTTPCookie {
    /// 把 WKWebView 的 Cookie 重建為只含標準屬性的 Cookie 再存入 `HTTPCookieStorage`。
    /// Cloudflare 的 cf_clearance 會帶 Partitioned 等屬性，原樣寫入後不會隨 App 的請求送出，導致驗證後仍被攔下。
    var forURLSession: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path,
        ]
        if isSecure { properties[.secure] = "TRUE" }
        if let expiresDate { properties[.expires] = expiresDate } else { properties[.discard] = "TRUE" }
        if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSitePolicy { properties[.sameSitePolicy] = sameSitePolicy.rawValue }
        return HTTPCookie(properties: properties)
    }
}
