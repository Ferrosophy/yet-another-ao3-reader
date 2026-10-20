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
            case .works: String(localized: "作品")
            case .series: String(localized: "系列")
            case .users: String(localized: "用戶")
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
struct WorkTagGroup: Hashable, Codable, Sendable {
    var title: String
    var tags: [WorkTag]
    /// Fandom 分組（翻譯開關與其他標籤分開）
    var isFandom = false
}

struct WorkTag: Hashable, Codable, Sendable {
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

/// AO3 作品語言（篩選用）。
struct AO3Language: Codable, Hashable, Identifiable, Sendable {
    var code: String
    var name: String
    var id: String { code }

    /// 全球使用人數（母語 + 第二語言）由多到少的大致排序；AO3 語言代碼含部分非標準寫法（ptBR 等）
    private static let speakerRank: [String] = [
        "en", "zh", "hi", "es", "ar", "fr", "bn", "ptBR", "pt-BR", "ptPT", "pt-PT", "pt", "ru", "ur", "id", "de", "ja",
        "mr", "te", "tr", "ta", "yue", "vi", "wuu", "tl", "fil", "ko", "fa", "ha", "sw", "jv", "it", "pa", "gu", "th",
        "kn", "am", "ms", "nan", "my", "pl", "hak", "ml", "uk", "or", "ro", "nl", "so", "ku", "ne", "si", "km", "az",
        "uz", "yo", "ig", "zu", "el", "hu", "cs", "sv", "be", "he", "sr", "bg", "da", "fi", "sk", "no", "nb", "nn",
        "hr", "ka", "hy", "lt", "sq", "mn", "lv", "et", "sl", "ga", "cy", "eu", "ca", "gl", "is", "la", "eo",
    ]

    /// 依全球使用人數排序；未列入排名的語言依名稱排在後面
    static func bySpeakers(_ languages: [AO3Language]) -> [AO3Language] {
        let rank = Dictionary(speakerRank.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return languages.sorted { lhs, rhs in
            switch (rank[lhs.code], rank[rhs.code]) {
            case let (l?, r?): l < r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// 尚未從 AO3 讀取完整清單時的備用選項
    static let fallback: [AO3Language] = [
        .init(code: "en", name: "English"), .init(code: "zh", name: "中文-普通话 國語"),
        .init(code: "ja", name: "日本語"), .init(code: "ko", name: "한국어"),
        .init(code: "es", name: "Español"), .init(code: "fr", name: "Français"),
        .init(code: "de", name: "Deutsch"), .init(code: "ru", name: "Русский"),
        .init(code: "pt-BR", name: "Português brasileiro"), .init(code: "it", name: "Italiano"),
    ]
}
