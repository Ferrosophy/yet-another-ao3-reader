import Foundation
import SwiftSoup

/// 頁面上的一個表單（action 與隱藏欄位），用於重現官網按鈕的提交，讓操作直接同步到 AO3 帳號。
struct FormSpec: Hashable, Sendable {
    struct Field: Hashable, Sendable {
        var name: String
        var value: String
    }

    var action: String
    var fields: [Field]

    var pairs: [(String, String)] { fields.map { ($0.name, $0.value) } }

    func value(_ name: String) -> String? { fields.first { $0.name == name }?.value }
}

/// 作品頁上與帳號相關的操作狀態（需登入才會出現在頁面上）。
struct WorkActions: Hashable, Sendable {
    var bookmark: FormSpec?
    var isBookmarked: Bool { bookmark.map { $0.action.contains("/bookmarks/") } ?? false }
    var bookmarkNotes = ""
    var bookmarkTags = ""
    var bookmarkPrivate = false

    var mark: FormSpec?
    var isMarkedForLater: Bool { mark?.action.hasSuffix("/mark_as_read") ?? false }

    var subscribe: FormSpec?
    var isSubscribed: Bool { subscribe.map { AO3Parser.isUnsubscribeForm($0) } ?? false }

    var authenticityToken: String?
}

/// 用戶頁或系列頁的訂閱按鈕。
struct SubscriptionTarget: Identifiable, Hashable, Sendable {
    var name: String
    var path: String
    var form: FormSpec?
    var id: String { path }
    var isSubscribed: Bool { form.map { AO3Parser.isUnsubscribeForm($0) } ?? false }
}

extension AO3Parser {
    /// - Parameter pageToken: 頁面 `<meta name="csrf-token">` 的值。AO3 部分表單（例如訂閱）不含
    ///   authenticity_token 隱藏欄位，而是由網頁腳本補上；缺少時 AO3 會拒絕請求，所以這裡自行補上。
    static func formSpec(_ form: Element, pageToken: String? = nil) throws -> FormSpec {
        var fields: [FormSpec.Field] = []
        for input in try form.select("input[type=hidden]") {
            let name = try input.attr("name")
            guard !name.isEmpty else { continue }
            fields.append(.init(name: name, value: try input.attr("value")))
        }
        if let pageToken, !pageToken.isEmpty, !fields.contains(where: { $0.name == "authenticity_token" }) {
            fields.append(.init(name: "authenticity_token", value: pageToken))
        }
        // 送出按鈕本身的值（例如 commit=Subscribe），與瀏覽器提交時一致
        if let button = try form.select("input[type=submit][name], button[type=submit][name]").first() {
            let name = try button.attr("name")
            if !name.isEmpty, !fields.contains(where: { $0.name == name }) {
                fields.append(.init(name: name, value: try button.attr("value")))
            }
        }
        // 多個 pseud 時以 select 選擇，取目前選中的值
        for select in try form.select("select") {
            let name = try select.attr("name")
            guard !name.isEmpty, let option = try select.select("option[selected]").first() ?? select.select("option").first() else { continue }
            fields.append(.init(name: name, value: try option.attr("value")))
        }
        return FormSpec(action: AO3Paths.path(fromHref: try form.attr("action")), fields: fields)
    }

    /// 已訂閱時表單 action 為 /users/<name>/subscriptions/<id> 且 _method=delete。
    static func isUnsubscribeForm(_ form: FormSpec) -> Bool {
        form.value("_method") == "delete" || form.action.range(of: #"/subscriptions/\d+$"#, options: .regularExpression) != nil
    }

    static func pageToken(_ doc: Document) throws -> String? {
        try doc.select("meta[name=csrf-token]").first()?.attr("content")
    }

    static func workActions(_ doc: Document) throws -> WorkActions? {
        var actions = WorkActions()
        let token = try pageToken(doc)
        if let form = try doc.select("#bookmark-form form").first() {
            actions.bookmark = try formSpec(form, pageToken: token)
            actions.bookmarkNotes = try form.select(#"textarea[name="bookmark[bookmarker_notes]"]"#).first()?.text() ?? ""
            actions.bookmarkTags = try form.select(#"input[name="bookmark[tag_string]"]"#).first()?.attr("value") ?? ""
            actions.bookmarkPrivate = try form.select(#"input[type=checkbox][name="bookmark[private]"]"#).first()?.hasAttr("checked") ?? false
        }
        if let form = try doc.select("li.mark form").first() {
            actions.mark = try formSpec(form, pageToken: token)
        }
        if let form = try doc.select("li.subscribe form").first() {
            actions.subscribe = try formSpec(form, pageToken: token)
        }
        actions.authenticityToken = token ?? actions.bookmark?.value("authenticity_token")
        // 未登入時頁面上沒有任何操作表單
        guard actions.bookmark != nil || actions.mark != nil || actions.subscribe != nil else { return nil }
        return actions
    }

    static func workActions(html: String) throws -> WorkActions? {
        try workActions(SwiftSoup.parse(html))
    }

    static func subscribeForm(html: String) throws -> FormSpec? {
        let doc = try SwiftSoup.parse(html)
        let token = try pageToken(doc)
        return try doc.select("li.subscribe form").first().map { try formSpec($0, pageToken: token) }
    }

    static func workAuthors(_ doc: Document) throws -> [WorkTag] {
        try doc.select("#workskin h3.byline a[rel=author]").array().map {
            WorkTag(name: try $0.text(), path: AO3Paths.path(fromHref: try $0.attr("href")))
        }
    }
}

extension AO3Client {
    /// 重新讀取作品頁（單章檢視，較輕量）以取得最新的操作狀態。
    func workActions(id: Int) async throws -> WorkActions? {
        let html = try await get("/works/\(id)", query: [URLQueryItem(name: "view_adult", value: "true")])
        return try AO3Parser.workActions(SwiftSoup.parse(html))
    }

    /// 作者（用戶頁）或系列頁的訂閱狀態。
    func subscriptionTarget(name: String, path: String) async throws -> SubscriptionTarget {
        let html = try await get(path)
        return SubscriptionTarget(name: name, path: path, form: try AO3Parser.subscribeForm(html: html))
    }

    func submit(_ form: FormSpec, extra: [(String, String)] = []) async throws {
        _ = try await postForm(form.action, fields: form.pairs + extra)
    }

    func saveBookmark(_ form: FormSpec, notes: String, tags: String, isPrivate: Bool, isUpdate: Bool) async throws {
        var extra: [(String, String)] = [
            ("bookmark[bookmarker_notes]", notes),
            ("bookmark[tag_string]", tags),
            ("bookmark[collection_names]", ""),
        ]
        // Rails 的 checkbox 會先送隱藏的 "0"，勾選時再送 "1"（後者生效）
        if isPrivate { extra.append(("bookmark[private]", "1")) }
        extra.append(("commit", isUpdate ? "Update" : "Create"))
        try await submit(form, extra: extra)
    }

    func deleteBookmark(_ form: FormSpec, token: String) async throws {
        _ = try await postForm(form.action, fields: [("_method", "delete"), ("authenticity_token", token)])
    }
}
