// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftSoup

/// 評論（?show_comments=true）與頁面提示訊息。
extension AO3Parser {

    /// 作品頁底部的評論。回覆巢狀在上層評論的 `ol.thread` 之內，這裡依文件順序攤平並記錄層級。
    static func comments(html: String, page: Int) throws -> CommentPage {
        let doc = try SwiftSoup.parse(html)
        var result: [WorkComment] = []
        // 評論元素 → 作者，用來找出回覆的對象（上層評論一定先出現）
        var authorsByElement: [ObjectIdentifier: String] = [:]
        for (index, item) in try doc.select("li.comment").array().enumerated() {
            let children = item.children().array()
            guard let body = children.first(where: { $0.tagName() == "blockquote" }) else { continue }
            let text = try richText(body)
            guard !text.isEmpty else { continue }

            var author = ""
            var posted: [String] = []
            var isGuest = false
            if let byline = children.first(where: { $0.tagName() == "h4" }) {
                author = try byline.select("a").first()?.text() ?? byline.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
                isGuest = try byline.select("span.role").first()?.text().localizedCaseInsensitiveContains("guest") ?? false
                if let parent = try byline.select("span.parent").first()?.text(), !parent.isEmpty { posted.append(parent) }
                if let date = try byline.select("span.posted").first()?.text(), !date.isEmpty { posted.append(date) }
            }

            // 回覆位於上層評論的 li 之內：祖先中有幾個 li.comment 就是第幾層，最近的一個就是回覆對象
            var depth = 0
            var replyTo: String?
            var ancestor = item.parent()
            while let current = ancestor {
                if current.tagName() == "li", current.hasClass("comment") {
                    if depth == 0 { replyTo = authorsByElement[ObjectIdentifier(current)] }
                    depth += 1
                }
                ancestor = current.parent()
            }
            let name = author.isEmpty ? "Anonymous" : author
            authorsByElement[ObjectIdentifier(item)] = name

            let id = item.id()
            result.append(WorkComment(
                id: id.isEmpty ? "comment-\(page)-\(index)" : id,
                author: name,
                isGuest: isGuest,
                posted: posted.joined(separator: " · "),
                text: text,
                depth: depth,
                replyTo: replyTo
            ))
        }
        return CommentPage(comments: result, page: page, hasNextPage: try hasNextPage(doc))
    }

    /// 頁面上的提示訊息（`div.flash`）：優先取與 Kudos 有關的，其次取第一則。`isError` 為錯誤提示。
    static func flashMessage(html: String) throws -> (isError: Bool, text: String)? {
        let doc = try SwiftSoup.parse(html)
        var first: (isError: Bool, text: String)?
        for flash in try doc.select("div.flash").array() {
            let text = try flash.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let classes = try flash.className().lowercased()
            let message = (isError: classes.contains("error") || classes.contains("alert"), text: text)
            if text.localizedCaseInsensitiveContains("kudos") { return message }
            if first == nil { first = message }
        }
        return first
    }
}
