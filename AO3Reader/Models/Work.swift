import Foundation

/// 搜尋結果、閱讀紀錄、書籤列表中的一個作品卡片（AO3 的 `li.blurb`）。
struct WorkSummary: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var authors: [String] = []
    var fandoms: [String] = []
    var rating: String?
    var warnings: [String] = []
    var categories: [String] = []
    var relationships: [String] = []
    var characters: [String] = []
    var freeforms: [String] = []
    var summary: String = ""
    var language: String?
    var words: String?
    var chapters: String?
    var kudos: String?
    var hits: String?
    var updated: String?
}

/// 一頁作品列表與分頁資訊。
struct WorkPage: Sendable {
    var works: [WorkSummary]
    var page: Int
    var hasNextPage: Bool
    /// 例如 "1 - 20 of 12,345 Works"
    var heading: String?
}

/// 完整作品內容（`?view_full_work=true`）。
struct WorkDetail: Sendable {
    let id: Int
    var title: String
    var authors: [String]
    var summary: String
    var chapters: [Chapter]
    var tagGroups: [WorkTagGroup] = []
    var series: [WorkTag] = []
    var authorLinks: [WorkTag] = []
    /// 登入後才有：書籤、稍後閱讀、訂閱
    var actions: WorkActions?
}

struct Chapter: Identifiable, Hashable, Sendable {
    /// 章節索引（從 0 開始）
    let id: Int
    var title: String
    var paragraphs: [Paragraph]
}

/// 沉浸式翻譯的最小單位：一個段落對應一段譯文。
struct Paragraph: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case body, heading, separator }

    /// 形如 "c0-p12"，在整部作品中唯一，同時作為譯文狀態的鍵。
    let id: String
    var text: String
    var kind: Kind = .body

    var isTranslatable: Bool { kind != .separator && !text.isEmpty }
}

/// 帳號頁面中可瀏覽的個人列表（需登入）。
enum UserListKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case history, markedForLater, bookmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "閱讀紀錄"
        case .markedForLater: "稍後閱讀"
        case .bookmarks: "書籤"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .markedForLater: "bookmark.circle"
        case .bookmarks: "bookmark"
        }
    }

    func path(username: String) -> (String, [URLQueryItem]) {
        switch self {
        case .history: ("/users/\(username)/readings", [])
        case .markedForLater: ("/users/\(username)/readings", [URLQueryItem(name: "show", value: "to-read")])
        case .bookmarks: ("/users/\(username)/bookmarks", [])
        }
    }
}
