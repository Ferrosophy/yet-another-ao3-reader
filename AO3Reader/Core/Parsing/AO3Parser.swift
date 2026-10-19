import Foundation
import SwiftSoup

/// 將 AO3（及結構相同的鏡像站）HTML 轉為模型。所有選擇器集中於此，方便官網改版時維護。
enum AO3Parser {

    // MARK: - Site / session

    static func looksLikeAO3(_ html: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        return (try? doc.select("#header, #main, #greeting").isEmpty()) == false
            && html.localizedCaseInsensitiveContains("archive")
    }

    /// 從頁首 `#greeting` 取得目前登入用戶名；未登入回傳 nil。
    static func loggedInUsername(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html),
              let link = try? doc.select("#greeting a.dropdown-toggle[href^=/users/], #greeting li.dropdown > a[href^=/users/]").first(),
              let href = try? link.attr("href")
        else { return nil }
        return href.split(separator: "/").dropFirst().first.map(String.init)
    }

    static func authenticityToken(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        if let input = try? doc.select("form#new_user input[name=authenticity_token], input[name=authenticity_token]").first() {
            return try? input.attr("value")
        }
        return try? doc.select("meta[name=csrf-token]").first()?.attr("content")
    }

    // MARK: - Work lists

    static func workPage(html: String, page: Int) throws -> WorkPage {
        let doc = try SwiftSoup.parse(html)
        var works: [WorkSummary] = []
        for blurb in try doc.select("li.blurb") {
            if let work = try workSummary(blurb) { works.append(work) }
        }
        let hasNext = try !doc.select("ol.pagination li.next a").isEmpty()
        let heading = try doc.select("#main h3.heading, #main h2.heading").first()?.text()
        return WorkPage(works: works, page: page, hasNextPage: hasNext, heading: heading)
    }

    private static func workSummary(_ blurb: Element) throws -> WorkSummary? {
        // 書籤列表可能包含系列/外部作品，只接受連往 /works/ 的項目
        guard let link = try blurb.select("h4.heading a[href^=/works/]").first(),
              let id = Int(try link.attr("href").split(separator: "/").dropFirst().first ?? "")
        else { return nil }

        func texts(_ css: String) throws -> [String] {
            try blurb.select(css).array().map { try $0.text() }
        }
        func text(_ css: String) throws -> String? {
            try blurb.select(css).first()?.text()
        }

        return WorkSummary(
            id: id,
            title: try link.text(),
            authors: try texts("h4.heading a[rel=author]"),
            fandoms: try texts("h5.fandoms a.tag"),
            rating: try blurb.select("ul.required-tags span.rating").first()?.attr("title"),
            warnings: try texts("ul.tags li.warnings a.tag"),
            categories: try blurb.select("ul.required-tags span.category").first()?.attr("title")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
            relationships: try texts("ul.tags li.relationships a.tag"),
            characters: try texts("ul.tags li.characters a.tag"),
            freeforms: try texts("ul.tags li.freeforms a.tag"),
            summary: try text("blockquote.userstuff.summary") ?? "",
            language: try text("dl.stats dd.language"),
            words: try text("dl.stats dd.words"),
            chapters: try text("dl.stats dd.chapters"),
            kudos: try text("dl.stats dd.kudos"),
            hits: try text("dl.stats dd.hits"),
            updated: try text("p.datetime")
        )
    }

    // MARK: - Work content

    static func workDetail(html: String, id: Int) throws -> WorkDetail {
        let doc = try SwiftSoup.parse(html)
        guard let container = try doc.select("#chapters").first() else {
            if html.contains("only available to registered users") || (try? doc.select("form#new_user").isEmpty()) == false {
                throw AO3Error.requiresLogin
            }
            throw AO3Error.parse(String(localized: "找不到作品內容 #chapters"))
        }

        let title = try doc.select("#workskin h2.title.heading").first()?.text() ?? "Work \(id)"
        let authors = try doc.select("#workskin h3.byline a[rel=author]").array().map { try $0.text() }
        let summary = try doc.select("#workskin > div.preface div.summary blockquote.userstuff").first()?.text() ?? ""

        var chapters: [Chapter] = []
        let children = container.children().array()
        let chapterDivs = children.filter { $0.tagName() == "div" && $0.hasClass("chapter") }
        if chapterDivs.isEmpty {
            // 單章作品：#chapters > div.userstuff
            let content = children.first { $0.hasClass("userstuff") } ?? container
            chapters.append(Chapter(id: 0, title: title, paragraphs: try paragraphs(in: content, chapter: 0)))
        } else {
            for (index, div) in chapterDivs.enumerated() {
                let chapterTitle = try div.select("h3.title").first()?.text() ?? "Chapter \(index + 1)"
                guard let content = try div.select("div.userstuff[role=article], div.userstuff.module").first()
                    ?? div.select("div.userstuff").first()
                else { continue }
                chapters.append(Chapter(id: index, title: chapterTitle, paragraphs: try paragraphs(in: content, chapter: index)))
            }
        }
        guard !chapters.isEmpty else { throw AO3Error.parse(String(localized: "作品沒有章節")) }
        return WorkDetail(
            id: id, title: title, authors: authors, summary: summary, chapters: chapters,
            tagGroups: try workTagGroups(doc), series: try workSeries(doc),
            authorLinks: try workAuthors(doc), actions: try workActions(doc)
        )
    }

    /// 把正文切成段落；`<br>` 保留為換行，`<hr>` 轉為分隔線。
    static func paragraphs(in content: Element, chapter: Int) throws -> [Paragraph] {
        try content.select("h3.landmark").remove()

        var result: [Paragraph] = []
        func append(_ text: String, _ kind: Paragraph.Kind) {
            result.append(Paragraph(id: "c\(chapter)-p\(result.count)", text: text, kind: kind))
        }

        let blocks = try content.select("p, h1, h2, h4, h5, h6, hr, li, pre")
        if blocks.isEmpty() {
            // 沒有 <p> 的純文字作品，以 <br><br> 分段
            for chunk in try blockText(content).components(separatedBy: "\n\n") {
                let text = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { append(text, .body) }
            }
            return result
        }

        for element in blocks {
            // 避免 <li><p>…</p></li> 重複
            if element.tagName() == "li", try !element.select("p").isEmpty() { continue }
            switch element.tagName() {
            case "hr":
                append("", .separator)
            case "h1", "h2", "h4", "h5", "h6":
                let text = try element.text()
                if !text.isEmpty { append(text, .heading) }
            default:
                let text = try blockText(element)
                if !text.isEmpty { append(text, .body) }
            }
        }
        return result
    }

    private static let lineBreakMarker = "\u{E000}"

    static func blockText(_ element: Element) throws -> String {
        let marked = try element.html().replacing(#/<br\s*/?>/#.ignoresCase(), with: lineBreakMarker)
        let text = try SwiftSoup.parseBodyFragment(marked).text()
        return text
            .components(separatedBy: lineBreakMarker)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
