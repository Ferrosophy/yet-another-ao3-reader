import Foundation

/// 對應 AO3 官方「Work Search」進階搜尋表單（/works/search）的全部欄位。
/// 不自行實作篩選邏輯，而是原樣產生官網參數，由 AO3 伺服器完成搜尋與篩選。
struct WorkSearchQuery: Hashable, Codable, Sendable {
    // 作品資訊
    var query = ""
    var title = ""
    var creators = ""
    /// 例如 "< 7 days"、"> 1 year"
    var revisedAt = ""
    var completion: TriState = .any
    var crossover: TriState = .any
    var singleChapter = false
    /// 例如 "> 10000"、"1000-5000"
    var wordCount = ""
    /// AO3 語言代碼，例如 "en"、"zh"、"ja"
    var languageID = ""

    // 作品標籤（以逗號分隔，與官網相同）
    var fandomNames = ""
    var rating: Rating?
    var warnings: Set<ArchiveWarning> = []
    var categories: Set<Category> = []
    var characterNames = ""
    var relationshipNames = ""
    var freeformNames = ""

    // 作品統計（支援 "> 1000"、"100-500" 等官網語法）
    var hits = ""
    var kudosCount = ""
    var commentsCount = ""
    var bookmarksCount = ""

    // 排序
    var sortColumn: SortColumn = .bestMatch
    var sortDirection: SortDirection = .desc

    var isEmpty: Bool { self == WorkSearchQuery(sortColumn: sortColumn, sortDirection: sortDirection) }

    func queryItems(page: Int) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        func add(_ key: String, _ value: String) {
            items.append(URLQueryItem(name: "work_search[\(key)]", value: value))
        }

        add("query", query)
        add("title", title)
        add("creators", creators)
        add("revised_at", revisedAt)
        add("complete", completion.rawValue)
        add("crossover", crossover.rawValue)
        add("single_chapter", singleChapter ? "1" : "0")
        add("word_count", wordCount)
        add("language_id", languageID)
        add("fandom_names", fandomNames)
        add("rating_ids", rating.map { String($0.rawValue) } ?? "")
        for warning in warnings.sorted(by: { $0.rawValue < $1.rawValue }) {
            items.append(URLQueryItem(name: "work_search[archive_warning_ids][]", value: String(warning.rawValue)))
        }
        for category in categories.sorted(by: { $0.rawValue < $1.rawValue }) {
            items.append(URLQueryItem(name: "work_search[category_ids][]", value: String(category.rawValue)))
        }
        add("character_names", characterNames)
        add("relationship_names", relationshipNames)
        add("freeform_names", freeformNames)
        add("hits", hits)
        add("kudos_count", kudosCount)
        add("comments_count", commentsCount)
        add("bookmarks_count", bookmarksCount)
        add("sort_column", sortColumn.rawValue)
        add("sort_direction", sortDirection.rawValue)
        items.append(URLQueryItem(name: "commit", value: "Search"))
        if page > 1 {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }
        return items
    }
}

extension WorkSearchQuery {
    enum TriState: String, CaseIterable, Codable, Sendable, Identifiable {
        case any = "", yes = "T", no = "F"
        var id: String { rawValue }
    }

    /// ID 與 AO3 資料庫中的標籤 ID 一致。
    enum Rating: Int, CaseIterable, Codable, Sendable, Identifiable {
        case notRated = 9, general = 10, teen = 11, mature = 12, explicit = 13
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .notRated: "Not Rated"
            case .general: "General Audiences"
            case .teen: "Teen And Up Audiences"
            case .mature: "Mature"
            case .explicit: "Explicit"
            }
        }
    }

    enum ArchiveWarning: Int, CaseIterable, Codable, Sendable, Identifiable {
        case choseNotToUse = 14, noneApply = 16, violence = 17, majorCharacterDeath = 18, nonCon = 19, underage = 20
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .choseNotToUse: "Creator Chose Not To Use Archive Warnings"
            case .noneApply: "No Archive Warnings Apply"
            case .violence: "Graphic Depictions Of Violence"
            case .majorCharacterDeath: "Major Character Death"
            case .nonCon: "Rape/Non-Con"
            case .underage: "Underage Sex"
            }
        }
    }

    enum Category: Int, CaseIterable, Codable, Sendable, Identifiable {
        case ff = 116, fm = 22, gen = 21, mm = 23, multi = 2246, other = 24
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .ff: "F/F"
            case .fm: "F/M"
            case .gen: "Gen"
            case .mm: "M/M"
            case .multi: "Multi"
            case .other: "Other"
            }
        }
    }

    enum SortColumn: String, CaseIterable, Codable, Sendable, Identifiable {
        case bestMatch = "_score"
        case author = "authors_to_sort_on"
        case title = "title_to_sort_on"
        case datePosted = "created_at"
        case dateUpdated = "revised_at"
        case wordCount = "word_count"
        case hits
        case kudos = "kudos_count"
        case comments = "comments_count"
        case bookmarks = "bookmarks_count"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .bestMatch: "最佳匹配"
            case .author: "作者"
            case .title: "標題"
            case .datePosted: "發佈日期"
            case .dateUpdated: "更新日期"
            case .wordCount: "字數"
            case .hits: "點擊"
            case .kudos: "Kudos"
            case .comments: "評論"
            case .bookmarks: "書籤"
            }
        }
    }

    enum SortDirection: String, CaseIterable, Codable, Sendable, Identifiable {
        case desc, asc
        var id: String { rawValue }
        var title: String { self == .desc ? "降冪" : "升冪" }
    }
}
