// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftSoup

/// 標籤、用戶、合集、訂閱、收件匣頁面的解析。選擇器依 otwarchive 的 view 範本：
/// tags/search、people/_author_blurb、collections/_collection_blurb、subscriptions/index、inbox/show。
extension AO3Parser {

    static func hasNextPage(_ doc: Document) throws -> Bool {
        try !doc.select("ol.pagination li.next a").isEmpty()
    }

    // MARK: - Tag search（/tags/search）

    static func tagResults(html: String, page: Int) throws -> ListPage<TagResult> {
        let doc = try SwiftSoup.parse(html)
        var results: [TagResult] = []
        for item in try doc.select("ol.tag.index > li") {
            guard let link = try item.select("a.tag, a[href^=/tags/]").first() else { continue }
            let span = try item.select("span").first()
            // span 內容形如 "Fandom: Harry Potter - J. K. Rowling ‎(123456)"
            let text = try (span ?? item).text()
            let type = text.split(separator: ":", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            let uses = text.firstMatch(of: #/\(([\d,]+)\)\s*$/#).map { String($0.1) }
            results.append(TagResult(
                name: try link.text(),
                type: type,
                uses: uses,
                isCanonical: span?.hasClass("canonical") ?? false,
                path: AO3Paths.path(fromHref: try link.attr("href"))
            ))
        }
        return ListPage(items: results, page: page, hasNextPage: try hasNextPage(doc))
    }

    // MARK: - People search（/people/search）

    static func peopleResults(html: String, page: Int) throws -> ListPage<PersonResult> {
        let doc = try SwiftSoup.parse(html)
        var results: [PersonResult] = []
        for blurb in try doc.select("ol.pseud.index > li") {
            guard let link = try blurb.select("h4.heading a[href^=/users/]").first() else { continue }
            results.append(PersonResult(
                name: try link.text(),
                path: AO3Paths.path(fromHref: try link.attr("href")),
                detail: try blurb.select("h5.heading").first()?.text(),
                summary: try blurb.select("blockquote.userstuff").first()?.text()
            ))
        }
        return ListPage(items: results, page: page, hasNextPage: try hasNextPage(doc))
    }

    // MARK: - Collections（/collections）

    static func collectionResults(html: String, page: Int) throws -> ListPage<CollectionResult> {
        let doc = try SwiftSoup.parse(html)
        var results: [CollectionResult] = []
        for blurb in try doc.select("li.collection.blurb") {
            guard let link = try blurb.select("h4.heading a[href^=/collections/]").first() else { continue }
            let name = try blurb.select("h4.heading span.name").first()?.text()
                .trimmingCharacters(in: CharacterSet(charactersIn: "() ")) ?? ""
            results.append(CollectionResult(
                title: try link.text(),
                name: name,
                path: AO3Paths.path(fromHref: try link.attr("href")),
                maintainers: try blurb.select("h4.heading a[href^=/users/]").array().map { try $0.text() },
                summary: try blurb.select("blockquote.userstuff.summary").first()?.text() ?? "",
                updated: try blurb.select("p.datetime").first()?.text()
            ))
        }
        return ListPage(items: results, page: page, hasNextPage: try hasNextPage(doc))
    }

    // MARK: - Subscriptions（/users/<name>/subscriptions?type=…）

    static func subscriptions(html: String, page: Int) throws -> ListPage<SubscriptionItem> {
        let doc = try SwiftSoup.parse(html)
        var results: [SubscriptionItem] = []
        for entry in try doc.select("dl.subscription.index > dt") {
            guard let link = try entry.select("a").first() else { continue }
            let path = AO3Paths.path(fromHref: try link.attr("href"))
            let kind: SubscriptionItem.Kind
            if path.hasPrefix("/works/") { kind = .works }
            else if path.hasPrefix("/series/") { kind = .series }
            else if path.hasPrefix("/users/") { kind = .users }
            else { continue }
            let authors = try entry.select("a[rel=author]").array().map { try $0.text() }
            results.append(SubscriptionItem(
                kind: kind,
                title: try link.text(),
                path: path,
                byline: authors.isEmpty ? nil : authors.joined(separator: ", ")
            ))
        }
        return ListPage(items: results, page: page, hasNextPage: try hasNextPage(doc))
    }

    // MARK: - Inbox（/users/<name>/inbox）

    static func inbox(html: String, page: Int) throws -> ListPage<InboxComment> {
        let doc = try SwiftSoup.parse(html)
        var results: [InboxComment] = []
        for item in try doc.select("ol.comment.index > li[id^=feedback_comment_]") {
            guard let heading = try item.select("h4.heading.byline, h4.heading").first() else { continue }
            let posted = try heading.select("span.posted.datetime").first()?.text()
            let links = try heading.select("a").array()
            let target = try links.first { try $0.attr("href").contains("/works/") || $0.attr("href").contains("/comments/") }
            let commenterLink = try links.first { try $0.attr("href").hasPrefix("/users/") && $0 !== target }
            let headingText = try heading.text()

            let commenter: String
            if let commenterLink {
                commenter = try commenterLink.text()
            } else {
                // 訪客或匿名作者：取 " on " 之前的文字
                commenter = headingText.components(separatedBy: " on ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            }

            results.append(InboxComment(
                id: try item.attr("id"),
                commenter: commenter,
                targetTitle: try target?.text() ?? "",
                workID: try target.flatMap { AO3Paths.workID(fromPath: try $0.attr("href")) },
                body: try item.select("blockquote.userstuff").first().map(blockText) ?? "",
                posted: posted,
                isUnread: item.hasClass("unread")
            ))
        }
        return ListPage(items: results, page: page, hasNextPage: try hasNextPage(doc))
    }

    // MARK: - Work meta tags（作品頁 dl.work.meta）

    static func workTagGroups(_ doc: Document) throws -> [WorkTagGroup] {
        let groups: [(String, String)] = [
            ("dd.rating", AO3Term.label(String(localized: "分級"), "Rating")),
            ("dd.warning", AO3Term.label(String(localized: "警告"), "Archive Warnings")),
            ("dd.category", AO3Term.label(String(localized: "分類"), "Category")),
            ("dd.fandom", AO3Term.label(String(localized: "原作"), "Fandoms")),
            ("dd.relationship", AO3Term.label(String(localized: "配對"), "Relationships")),
            ("dd.character", AO3Term.label(String(localized: "角色"), "Characters")),
            ("dd.freeform", AO3Term.label(String(localized: "其他標籤"), "Additional Tags")),
        ]
        var result: [WorkTagGroup] = []
        for (css, title) in groups {
            let tags = try doc.select("dl.work.meta \(css) a.tag").array().map {
                WorkTag(name: try $0.text(), path: AO3Paths.path(fromHref: try $0.attr("href")))
            }
            if !tags.isEmpty { result.append(WorkTagGroup(title: title, tags: tags, isFandom: css == "dd.fandom",
                                                          kind: String(css.dropFirst(3)))) }
        }
        return result
    }

    /// 作品頁「Download」選單中的各格式連結，鍵為小寫副檔名。
    static func workDownloads(_ doc: Document) throws -> [String: String] {
        var result: [String: String] = [:]
        for link in try doc.select("li.download a[href*=/downloads/]").array() {
            let href = try link.attr("href")
            let path = href.split(separator: "?").first.map(String.init) ?? href
            guard let ext = path.split(separator: ".").last?.lowercased(), !ext.contains("/") else { continue }
            result[ext] = href
        }
        return result
    }

    /// 作品頁的分級、標籤與統計，組成與列表卡片相同的資料。
    static func workInfo(_ doc: Document, id: Int, title: String, authors: [String], summary: String) throws -> WorkSummary {
        func tags(_ css: String) throws -> [String] {
            try doc.select("dl.work.meta \(css) a.tag").array().map { try $0.text() }
        }
        func stat(_ css: String) throws -> String? {
            let text = try doc.select("dl.stats \(css)").first()?.text()
            return text?.isEmpty == false ? text : nil
        }
        return WorkSummary(
            id: id, title: title, authors: authors,
            fandoms: try tags("dd.fandom"),
            rating: try tags("dd.rating").first,
            warnings: try tags("dd.warning"),
            categories: try tags("dd.category"),
            relationships: try tags("dd.relationship"),
            characters: try tags("dd.character"),
            freeforms: try tags("dd.freeform"),
            summary: summary,
            language: try doc.select("dl.work.meta dd.language").first()?.text(),
            words: try stat("dd.words"),
            chapters: try stat("dd.chapters"),
            kudos: try stat("dd.kudos"),
            hits: try stat("dd.hits"),
            updated: try stat("dd.status") ?? stat("dd.published")
        )
    }

    /// 作品所屬系列（dd.series 內的連結）。
    static func workSeries(_ doc: Document) throws -> [WorkTag] {
        try doc.select("dl.work.meta dd.series a[href^=/series/]").array().map {
            WorkTag(name: try $0.text(), path: AO3Paths.path(fromHref: try $0.attr("href")))
        }
    }
}

extension AO3Parser {
    /// Work Search 表單中的語言選項（value 為 AO3 語言代碼）。
    static func languageOptions(html: String) throws -> [AO3Language] {
        let doc = try SwiftSoup.parse(html)
        return try doc.select("select#work_search_language_id option, select[name=\"work_search[language_id]\"] option")
            .array()
            .compactMap { option in
                let code = try option.attr("value")
                guard !code.isEmpty else { return nil }
                return AO3Language(code: code, name: try option.text())
            }
    }
}
