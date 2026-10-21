import Foundation
import os

/// 展示模式（設定 › 連點版本號 › 除錯 › 展示）：來源指向虛構的示範站，作品、作者與評論全部由 AI 生成，
/// 用於截取宣傳圖，不會出現任何真實作者或作品。內容由 `AO3Client` 直接回傳，不送出網路請求。
enum DemoSite {
    static let host = "demo.yaao3r.invalid"
    static let baseURL = URL(string: "https://demo.yaao3r.invalid")!

    /// 展示來源（不會被保存，重新開啟 App 後回到原本的來源）
    static let source = AO3Source(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000D3A0")!,
        name: String(localized: "展示（虛構內容）"),
        baseURL: baseURL,
        isBuiltIn: true
    )

    static let languages = [AO3Language(code: "en", name: "English")]

    /// 一部示範作品與它的評論
    struct Work: Sendable {
        var detail: WorkDetail
        var comments: [WorkComment]
    }

    private static let pageSize = 20
    private static let givenKudos = OSAllocatedUnfairLock(initialState: Set<Int>())

    private static var summaries: [WorkSummary] { works.map(\.detail.summaryInfo) }

    // MARK: - Works

    static func searchPage(_ query: WorkSearchQuery, page: Int) -> WorkPage {
        let matched = summaries.filter { query.matches($0, languageCodes: ["English": "en"]) }
        return paged(query.sorted(matched), page: page)
    }

    static func detail(id: Int) throws -> WorkDetail {
        guard let work = works.first(where: { $0.detail.id == id }) else { throw AO3Error.http(404) }
        return work.detail
    }

    /// 標籤頁與作者頁的作品列表
    static func worksPage(path: String, page: Int) -> WorkPage {
        let parts = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        var list = summaries
        if parts.count >= 2, parts[0] == "tags" {
            let name = untag(parts[1]).lowercased()
            list = list.filter { tagNames($0).contains { $0.lowercased() == name } }
        } else if parts.count >= 2, parts[0] == "users" {
            let name = parts[1].lowercased()
            list = list.filter { $0.authors.contains { $0.lowercased() == name } }
        }
        return paged(list, page: page)
    }

    private static func paged(_ list: [WorkSummary], page: Int) -> WorkPage {
        let start = (max(page, 1) - 1) * pageSize
        let end = min(start + pageSize, list.count)
        let slice = start < end ? Array(list[start..<end]) : []
        return WorkPage(works: slice, page: page, hasNextPage: end < list.count,
                        heading: "\(min(start + 1, list.count)) - \(end) of \(list.count) Works")
    }

    // MARK: - Tags

    private static func tagNames(_ work: WorkSummary) -> [String] {
        work.fandoms + work.relationships + work.characters + work.freeforms + work.warnings + work.categories
    }

    /// 與 `AO3Paths.tagParam` 相反：還原標籤名稱中被替換的字元
    private static func untag(_ param: String) -> String {
        param.replacingOccurrences(of: "*s*", with: "/")
            .replacingOccurrences(of: "*a*", with: "&")
            .replacingOccurrences(of: "*d*", with: ".")
            .replacingOccurrences(of: "*q*", with: "?")
            .replacingOccurrences(of: "*h*", with: "#")
    }

    static func tagResults(name: String, type: TagSearchType, page: Int) -> ListPage<TagResult> {
        let all = summaries
        var counts: [String: Int] = [:]
        var kinds: [String: String] = [:]
        func add(_ names: [String], _ kind: String) {
            for tag in names {
                counts[tag, default: 0] += 1
                kinds[tag] = kind
            }
        }
        for work in all {
            add(work.fandoms, TagSearchType.fandom.rawValue)
            add(work.characters, TagSearchType.character.rawValue)
            add(work.relationships, TagSearchType.relationship.rawValue)
            add(work.freeforms, TagSearchType.freeform.rawValue)
        }
        let results = counts.keys
            .filter { tag in
                (type == .any || kinds[tag] == type.rawValue) && (name.isEmpty || tag.localizedCaseInsensitiveContains(name))
            }
            .sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
            .map { tag in
                TagResult(name: tag, type: kinds[tag] ?? "", uses: String(counts[tag] ?? 0), isCanonical: true,
                          path: "/tags/\(AO3Paths.tagParam(tag))/works")
            }
        return ListPage(items: results, page: page, hasNextPage: false)
    }

    static func autocomplete(_ kind: AutocompleteKind, term: String) -> [String] {
        let all = summaries
        var names: [String]
        switch kind {
        case .fandom: names = all.flatMap(\.fandoms)
        case .character: names = all.flatMap(\.characters)
        case .relationship: names = all.flatMap(\.relationships)
        case .freeform: names = all.flatMap(\.freeforms)
        case .tag: names = all.flatMap { $0.fandoms + $0.characters + $0.relationships + $0.freeforms }
        case .pseud: names = all.flatMap(\.authors)
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted && $0.localizedCaseInsensitiveContains(term) }
    }

    // MARK: - Comments and kudos

    static func comments(workID: Int, page: Int) -> CommentPage {
        let list = page == 1 ? (works.first { $0.detail.id == workID }?.comments ?? []) : []
        return CommentPage(comments: list, page: page, hasNextPage: false)
    }

    /// 第一次回傳「已給」，之後回傳「已經給過」（只記在這次執行中）
    static func leaveKudos(workID: Int) -> KudosResult {
        givenKudos.withLock { $0.insert(workID).inserted } ? .given : .alreadyGiven
    }
}
