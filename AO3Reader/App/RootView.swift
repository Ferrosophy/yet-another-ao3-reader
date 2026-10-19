import SwiftUI

/// iOS 26 Liquid Glass 分頁：系統自動以玻璃材質渲染浮動 Tab Bar，
/// 搜尋分頁使用 `.search` 角色，捲動時縮小 Tab Bar 讓內容滿版。
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            Tab("最新", systemImage: "sparkles.rectangle.stack") {
                NavigationStack {
                    LatestWorksView()
                        .withWorkNavigation()
                        // 切換來源（官網 ↔ 鏡像）時以新來源重新載入
                        .id(app.sources.selectedID)
                }
            }
            Tab("帳號", systemImage: "person.crop.circle") {
                NavigationStack {
                    AccountView()
                        .withWorkNavigation()
                        // 切換來源（官網 ↔ 鏡像）時以新來源重新載入
                        .id(app.sources.selectedID)
                }
            }
            Tab("設定", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView()
                }
            }
            Tab(role: .search) {
                NavigationStack {
                    SearchView()
                        .withWorkNavigation()
                        // 切換來源（官網 ↔ 鏡像）時以新來源重新載入
                        .id(app.sources.selectedID)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// 導航目標：點擊作品卡片進入閱讀器。
struct WorkRoute: Hashable {
    let id: Int
    let title: String
}

private struct WorkNavigation: ViewModifier {
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        content.navigationDestination(for: WorkRoute.self) { route in
            ReaderView(model: ReaderViewModel(route: route, app: app))
        }
    }
}

extension View {
    func withWorkNavigation() -> some View { modifier(WorkNavigation()) }
}
