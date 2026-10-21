// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 導航目標：點擊作品卡片進入閱讀器。
struct WorkRoute: Hashable {
    let id: Int
    let title: String
    /// 每次建立都不同：避免列表把「與導航路徑上相同的作品」顯示為選取狀態
    /// （例如從作品進入其系列時，系列列表中的該作品會一直保持加暗）
    var nonce = UUID()
}

/// 導航目標：任意作品列表頁（標籤、合集、系列、用戶作品）。
/// `filterable` 為 true 時提供與官網相同的「Sort and Filter」篩選。
struct WorkListRoute: Hashable {
    var title: String
    var path: String
    var baseQuery: [URLQueryItem] = []
    var filterable = false

    /// 標籤下的所有作品：/works?tag_id=<to_param>，可再篩選。
    static func tag(name: String, param: String? = nil) -> WorkListRoute {
        WorkListRoute(
            title: name,
            path: "/works",
            baseQuery: [URLQueryItem(name: "tag_id", value: param ?? AO3Paths.tagParam(name))],
            filterable: true
        )
    }

    /// 由作品頁或搜尋結果中的標籤連結（/tags/<param>[/works]）建立。
    static func tag(name: String, path: String) -> WorkListRoute {
        tag(name: name, param: AO3Paths.tagParam(fromPath: path))
    }

    static func collection(_ collection: CollectionResult) -> WorkListRoute {
        WorkListRoute(title: collection.title, path: collection.path + "/works", filterable: true)
    }

    static func person(name: String, path: String) -> WorkListRoute {
        WorkListRoute(title: name, path: path.hasSuffix("/works") ? path : path + "/works", filterable: true)
    }

    static func series(name: String, path: String) -> WorkListRoute {
        WorkListRoute(title: name, path: path, filterable: true)
    }
}

private struct WorkNavigation: ViewModifier {
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: WorkRoute.self) { route in
                ReaderView(model: ReaderViewModel(route: route, app: app))
            }
            .navigationDestination(for: WorkListRoute.self) { route in
                WorkListScreen(route: route)
            }
    }
}

extension View {
    func withWorkNavigation() -> some View { modifier(WorkNavigation()) }
}

/// 以程式推入作品列表（標籤、系列）。各分頁的 NavigationStack 使用明確的路徑，
/// 推入的頁面與 NavigationLink(value:) 在同一條路徑上，返回時只退一層。
/// 翻頁模式的資訊頁放在 UIKit 容器中無法使用 NavigationLink，也透過它推入。
struct OpenWorkListAction: @unchecked Sendable {
    var handler: @MainActor (WorkListRoute) -> Void = { _ in }

    @MainActor func callAsFunction(_ route: WorkListRoute) { handler(route) }
}

extension EnvironmentValues {
    @Entry var openWorkList = OpenWorkListAction()
}
