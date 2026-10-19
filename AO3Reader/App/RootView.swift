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
        .tint(app.appearance.accentColor)
        .preferredColorScheme(app.appearance.config.colorScheme.scheme)
        // 介面字體：未指定樣式的文字用 body，各處 .appFont(...) 依此換字體；系統字體則以 fontDesign 套用
        .environment(\.interfaceFont, app.appearance.interfaceFontChoice)
        .font(InterfaceFont.font(app.appearance.interfaceFontChoice, style: .body))
        .fontDesign(InterfaceFont.design(app.appearance.interfaceFontChoice))
        .environment(\.locale, InterfaceLanguage.selectedCode.map(Locale.init(identifier:)) ?? .autoupdatingCurrent)
        .onChange(of: app.appearance.interfaceFontChoice, initial: true) {
            InterfaceFont.applyNavigationBarAppearance(app.appearance.interfaceFontChoice)
        }
    }
}
