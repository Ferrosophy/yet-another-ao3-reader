import Combine
import SwiftUI

/// 打開 App 後的第一個分頁。
enum StartTab: String, CaseIterable, Identifiable {
    case bookshelf, browse

    var id: String { rawValue }
    var title: String { self == .bookshelf ? String(localized: "書架") : String(localized: "瀏覽") }

    static let storageKey = "app.startTab"
}

/// iOS 26 Liquid Glass 分頁：系統自動以玻璃材質渲染浮動 Tab Bar，
/// 搜尋分頁使用 `.search` 角色，捲動時縮小 Tab Bar 讓內容滿版。
struct RootView: View {
    enum TabID: Hashable { case bookshelf, browse, account, settings, search }

    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: TabID = {
        let start = UserDefaults.standard.string(forKey: StartTab.storageKey).flatMap(StartTab.init) ?? .browse
        return start == .bookshelf ? .bookshelf : .browse
    }()
    @State private var challenge: ChallengePage?
    /// 各分頁的導覽路徑
    @State private var paths: [TabID: NavigationPath] = [:]

    private struct ChallengePage: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private func path(_ tab: TabID) -> Binding<NavigationPath> {
        Binding(get: { paths[tab] ?? NavigationPath() }, set: { paths[tab] = $0 })
    }

    private func openWorkList(_ tab: TabID) -> OpenWorkListAction {
        OpenWorkListAction { route in paths[tab, default: NavigationPath()].append(route) }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("書架", systemImage: "books.vertical", value: TabID.bookshelf) {
                NavigationStack(path: path(.bookshelf)) {
                    BookshelfView()
                        .withWorkNavigation()
                }
                .environment(\.openWorkList, openWorkList(.bookshelf))
            }
            Tab("瀏覽", systemImage: "sparkles.rectangle.stack", value: TabID.browse) {
                NavigationStack(path: path(.browse)) {
                    LatestWorksView()
                        .withWorkNavigation()
                        // 切換來源（官網 ↔ 鏡像）時以新來源重新載入
                        .id(app.sources.selectedID)
                }
                .environment(\.openWorkList, openWorkList(.browse))
            }
            Tab("帳號", systemImage: "person.crop.circle", value: TabID.account) {
                NavigationStack(path: path(.account)) {
                    AccountView()
                        .withWorkNavigation()
                        // 切換來源（官網 ↔ 鏡像）時以新來源重新載入
                        .id(app.sources.selectedID)
                }
                .environment(\.openWorkList, openWorkList(.account))
            }
            Tab("設定", systemImage: "gearshape", value: TabID.settings) {
                NavigationStack(path: path(.settings)) {
                    SettingsView()
                        .withWorkNavigation()
                }
                .environment(\.openWorkList, openWorkList(.settings))
            }
            Tab(value: TabID.search, role: .search) {
                NavigationStack(path: path(.search)) {
                    SearchView()
                        .withWorkNavigation()
                        // 切換來源（官網 ↔ 鏡像）時以新來源重新載入
                        .id(app.sources.selectedID)
                }
                .environment(\.openWorkList, openWorkList(.search))
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
        // AO3 請求遇到 Cloudflare 人機驗證時彈出驗證頁（同時只顯示一個）
        .onReceive(NotificationCenter.default.publisher(for: .ao3CloudflareChallenge).receive(on: DispatchQueue.main)) { note in
            guard challenge == nil, let url = note.userInfo?["url"] as? URL else { return }
            challenge = ChallengePage(url: url)
        }
        .sheet(item: $challenge) { page in
            CloudflareChallengeView(url: page.url)
        }
        // 個人資料同步：開啟與回到前景時拉取、進入背景時上傳
        .task { await app.sync.syncNow() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active, .background: Task { await app.sync.syncNow() }
            default: break
            }
        }
    }
}
