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

    // 僅用於標籤 / 合集作品列表的篩選（/works?tag_id=…）
    var excludedTagNames = ""
    var wordsFrom = ""
    var wordsTo = ""

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
        add("excluded_tag_names", excludedTagNames)
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
    /// 標籤 / 合集作品列表右側「Sort and Filter」表單的參數（otwarchive works/_filters）。
    /// 標籤欄位全部併入 other_tag_names，由 AO3 依名稱比對。
    func filterItems(page: Int) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        func add(_ key: String, _ value: String) {
            items.append(URLQueryItem(name: "work_search[\(key)]", value: value))
        }
        // 標籤頁不支援「最佳匹配」，預設依更新日期
        add("sort_column", sortColumn == .bestMatch ? SortColumn.dateUpdated.rawValue : sortColumn.rawValue)
        let included = [fandomNames, characterNames, relationshipNames, freeformNames]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        add("other_tag_names", included)
        add("excluded_tag_names", excludedTagNames)
        add("crossover", crossover.rawValue)
        add("complete", completion.rawValue)
        // 與詳細搜尋相同的欄位：字數與更新時間換成篩選表單的範圍參數，
        // 篩選表單沒有的欄位（標題、作者、統計數字、單章）以 AO3 的欄位語法併入「在結果中搜尋」
        let words = Self.range(wordCount)
        add("words_from", words.from ?? wordsFrom)
        add("words_to", words.to ?? wordsTo)
        let dates = Self.dateRange(revisedAt)
        add("date_from", dates.from ?? "")
        add("date_to", dates.to ?? "")
        add("query", filterQuery)
        add("language_id", languageID)
        add("sort_direction", sortDirection.rawValue)
        if let rating {
            items.append(URLQueryItem(name: "include_work_search[rating_ids][]", value: String(rating.rawValue)))
        }
        for warning in warnings.sorted(by: { $0.rawValue < $1.rawValue }) {
            items.append(URLQueryItem(name: "include_work_search[archive_warning_ids][]", value: String(warning.rawValue)))
        }
        for category in categories.sorted(by: { $0.rawValue < $1.rawValue }) {
            items.append(URLQueryItem(name: "include_work_search[category_ids][]", value: String(category.rawValue)))
        }
        items.append(URLQueryItem(name: "commit", value: "Sort and Filter"))
        if page > 1 {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }
        return items
    }

    /// 「在結果中搜尋」：關鍵字加上篩選表單沒有的欄位
    private var filterQuery: String {
        var parts = [query.trimmingCharacters(in: .whitespaces)]
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "") + "\"" }
        if !title.isEmpty { parts.append("title:" + quoted(title)) }
        if !creators.isEmpty { parts.append("creators:" + quoted(creators)) }
        for (field, value) in [("hits", hits), ("kudos_count", kudosCount), ("comments_count", commentsCount),
                               ("bookmarks_count", bookmarksCount)] {
            if let condition = Self.fieldCondition(value) { parts.append("\(field):\(condition)") }
        }
        if singleChapter { parts.append("expected_number_of_chapters:1") }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 「> 1000」「< 50」「100-500」→ 搜尋語法 >1000、<50、[100 TO 500]
    static func fieldCondition(_ text: String) -> String? {
        let trimmed = text.replacingOccurrences(of: " ", with: "")
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "-")
        if parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil { return "[\(parts[0]) TO \(parts[1])]" }
        return trimmed
    }

    /// 「> 1000」「< 5000」「1000-5000」→ 字數範圍（from / to）
    static func range(_ text: String) -> (from: String?, to: String?) {
        let trimmed = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty else { return (nil, nil) }
        if trimmed.hasPrefix(">"), let value = Int(trimmed.dropFirst()) { return (String(value + 1), nil) }
        if trimmed.hasPrefix("<"), let value = Int(trimmed.dropFirst()) { return (nil, String(max(value - 1, 0))) }
        let parts = trimmed.split(separator: "-")
        if parts.count == 2 { return (String(parts[0]), String(parts[1])) }
        if let value = Int(trimmed) { return (String(value), String(value)) }
        return (nil, nil)
    }

    /// 「< 7 days」（最近 7 天內更新）→ date_from；「> 1 years」（超過一年未更新）→ date_to
    static func dateRange(_ text: String, now: Date = Date()) -> (from: String?, to: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: /([<>])\s*(\d+)\s*(day|week|month|year)s?/),
              let amount = Int(match.2) else { return (nil, nil) }
        let component: Calendar.Component = switch match.3 {
        case "week": .weekOfYear
        case "month": .month
        case "year": .year
        default: .day
        }
        guard let date = Calendar(identifier: .gregorian).date(byAdding: component, value: -amount, to: now) else { return (nil, nil) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        return match.1 == "<" ? (day, nil) : (nil, day)
    }

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
            case .bestMatch: String(localized: "最佳匹配")
            case .author: String(localized: "作者")
            case .title: String(localized: "標題")
            case .datePosted: String(localized: "發佈日期")
            case .dateUpdated: String(localized: "更新日期")
            case .wordCount: String(localized: "字數")
            case .hits: String(localized: "點擊")
            case .kudos: "Kudos"
            case .comments: String(localized: "評論")
            case .bookmarks: String(localized: "書籤")
            }
        }
    }

    enum SortDirection: String, CaseIterable, Codable, Sendable, Identifiable {
        case desc, asc
        var id: String { rawValue }
        var title: String { self == .desc ? String(localized: "降序") : String(localized: "升序") }
    }
}

extension WorkSearchQuery {
    /// 在本機判斷作品是否符合篩選條件（官網無法篩選的列表使用）
    func matches(_ work: WorkSummary, languageCodes: [String: String]) -> Bool {
        func number(_ text: String?) -> Int? { Int((text ?? "").filter(\.isNumber)) }
        func names(_ text: String) -> [String] {
            text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        }
        let tags = Set((work.fandoms + work.relationships + work.characters + work.freeforms + work.warnings
            + work.categories).map { $0.lowercased() })

        let included = [fandomNames, characterNames, relationshipNames, freeformNames].flatMap(names)
        guard included.allSatisfy(tags.contains) else { return false }
        guard !names(excludedTagNames).contains(where: tags.contains) else { return false }
        if let rating, work.rating != rating.title { return false }
        if !warnings.isEmpty, !warnings.contains(where: { work.warnings.contains($0.title) }) { return false }
        if !categories.isEmpty, !categories.contains(where: { work.categories.contains($0.title) }) { return false }
        if completion != .any {
            let parts = (work.chapters ?? "").split(separator: "/").map(String.init)
            let complete = parts.count == 2 && parts[0] == parts[1]
            if (completion == .yes) != complete { return false }
        }
        if crossover != .any, (crossover == .yes) != (work.fandoms.count > 1) { return false }
        func within(_ value: Int, _ condition: String) -> Bool {
            let range = Self.range(condition)
            if let from = range.from.flatMap(Int.init), value < from { return false }
            if let to = range.to.flatMap(Int.init), value > to { return false }
            return true
        }
        let words = number(work.words) ?? 0
        guard within(words, wordCount) else { return false }
        if let minimum = Int(wordsFrom), words < minimum { return false }
        if let maximum = Int(wordsTo), words > maximum { return false }
        guard within(number(work.hits) ?? 0, hits), within(number(work.kudos) ?? 0, kudosCount) else { return false }
        if !title.isEmpty, !work.title.localizedCaseInsensitiveContains(title) { return false }
        if !creators.isEmpty, !work.authors.contains(where: { $0.localizedCaseInsensitiveContains(creators) }) { return false }
        if singleChapter, !(work.chapters ?? "").hasPrefix("1/") { return false }
        let dates = Self.dateRange(revisedAt)
        if dates.from != nil || dates.to != nil, let updated = work.updated {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMM yyyy"
            let output = DateFormatter()
            output.locale = Locale(identifier: "en_US_POSIX")
            output.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: updated).map(output.string(from:)) {
                if let from = dates.from, date < from { return false }
                if let to = dates.to, date > to { return false }
            }
        }
        if !languageID.isEmpty, let language = work.language, languageCodes[language] != languageID { return false }
        let keyword = query.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            let haystack = ([work.title, work.summary] + work.authors + Array(tags)).joined(separator: "\n")
            if !haystack.localizedCaseInsensitiveContains(keyword) { return false }
        }
        return true
    }

    /// 依排序欄位在本機排序（官網的排序方式；無法在本機判斷的欄位保持原順序）
    func sorted(_ works: [WorkSummary]) -> [WorkSummary] {
        func number(_ text: String?) -> Int { Int((text ?? "").filter(\.isNumber)) ?? 0 }
        switch sortColumn {
        case .wordCount: return works.sorted { number($0.words) > number($1.words) }
        case .hits: return works.sorted { number($0.hits) > number($1.hits) }
        case .kudos: return works.sorted { number($0.kudos) > number($1.kudos) }
        case .title: return works.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: return works.sorted { ($0.authors.first ?? "").localizedStandardCompare($1.authors.first ?? "") == .orderedAscending }
        default: return works
        }
    }
}
