import Foundation

/// 非作品類列表（標籤、用戶、合集、訂閱、收件匣）的一頁。
struct ListPage<Item: Sendable>: Sendable {
    var items: [Item]
    var page: Int
    var hasNextPage: Bool
}

/// Tag Search 結果。`path` 為 AO3 標籤頁路徑（/tags/<to_param>）。
struct TagResult: Identifiable, Hashable, Sendable {
    var name: String
    var type: String
    var uses: String?
    var isCanonical: Bool
    var path: String
    var id: String { path }
}

/// People Search 結果。
struct PersonResult: Identifiable, Hashable, Sendable {
    var name: String
    /// 例如 "/users/foo/pseuds/bar"
    var path: String
    var detail: String?
    var summary: String?
    var id: String { path }
}

/// Collections 列表項目。
struct CollectionResult: Identifiable, Hashable, Sendable {
    var title: String
    /// 合集代號，例如 "yuletide2025"
    var name: String
    var path: String
    var maintainers: [String]
    var summary: String
    var updated: String?
    var id: String { path }
}

/// 訂閱：作品、系列或用戶。
struct SubscriptionItem: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case works, series, users
        var id: String { rawValue }
        var title: String {
            switch self {
            case .works: "作品"
            case .series: "系列"
            case .users: "用戶"
            }
        }
    }

    var kind: Kind
    var title: String
    var path: String
    var byline: String?
    var id: String { path }

    var workID: Int? {
        guard kind == .works else { return nil }
        return AO3Paths.workID(fromPath: path)
    }
}

/// 收件匣中的一則評論。
struct InboxComment: Identifiable, Hashable, Sendable {
    var id: String
    var commenter: String
    var targetTitle: String
    var workID: Int?
    var body: String
    var posted: String?
    var isUnread: Bool
}

/// 作品頁的標籤分組（Rating、Warnings、Fandoms…），每個標籤可點開該標籤下的作品。
struct WorkTagGroup: Hashable, Sendable {
    var title: String
    var tags: [WorkTag]
}

struct WorkTag: Hashable, Sendable {
    var name: String
    /// 通常為 /tags/<to_param>/works
    var path: String
}

enum AO3Paths {
    /// AO3 的 Tag#to_param：把網址不友善的字元換成 *x* 形式。
    static func tagParam(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "*s*")
            .replacingOccurrences(of: "&", with: "*a*")
            .replacingOccurrences(of: ".", with: "*d*")
            .replacingOccurrences(of: "?", with: "*q*")
            .replacingOccurrences(of: "#", with: "*h*")
    }

    /// 從 "/tags/<param>/works" 或 "/tags/<param>" 取出 tag_id 參數。
    static func tagParam(fromPath path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "tags" else { return nil }
        return String(parts[1])
    }

    static func workID(fromPath path: String) -> Int? {
        let parts = path.split(separator: "/")
        guard let index = parts.firstIndex(of: "works"), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
    }

    /// 只保留路徑部分（去掉主機與查詢參數），讓鏡像來源也能使用。
    /// 回傳**未編碼**路徑：`AO3Client.url` 會以 `appending(path:)` 重新編碼，避免 %20 變成 %2520。
    static func path(fromHref href: String) -> String {
        if let url = URL(string: href), url.host() != nil {
            return url.path(percentEncoded: false)
        }
        let raw = String(href.prefix { $0 != "?" && $0 != "#" })
        return raw.removingPercentEncoding ?? raw
    }
}
