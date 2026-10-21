import Foundation

/// 作品頁底部的一則評論（含回覆，以 `depth` 表示層級）。
struct WorkComment: Identifiable, Hashable, Sendable {
    let id: String
    var author: String
    var isGuest = false
    /// 評論所屬章節與時間，例如「on Chapter 2 · Mon 01 Jan 2024 12:00AM UTC」
    var posted = ""
    var text: String
    /// 0 為頂層評論，回覆逐層加一
    var depth = 0
}

/// 一頁評論與分頁資訊。
struct CommentPage: Sendable {
    var comments: [WorkComment]
    var page: Int
    var hasNextPage: Bool
}

/// 給作品 Kudos 的結果
enum KudosResult: Equatable, Sendable {
    case given
    case alreadyGiven
}
