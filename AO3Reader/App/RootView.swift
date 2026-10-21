import Combine
import SwiftUI

/// 打開 App 後的第一個分頁。
enum StartTab: String, CaseIterable, Identifiable {
    case bookshelf, browse

    var id: String { rawValue }
    var title: String { self == .bookshelf ? String(localized: "離線") : String(localized: "瀏覽") }

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
    /// 驗證頁上次關閉的時間與最近彈出的時間（避免反覆彈出、關閉）
    @State private var challengeClosedAt: Date?
    @State private var challengeTimes: [Date] = []
    @State private var showsChallengeHelp = false
    @State private var pendingChallengeURL: URL?
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
            Tab("離線", systemImage: "arrow.down.circle", value: TabID.bookshelf) {
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
            // 新手引導顯示中不彈出（引導裡的連線檢測不經過這裡，但背景的同步、離線下載可能觸發）
            guard challenge == nil, !app.showsOnboarding, let url = note.userInfo?["url"] as? URL else { return }
            // 剛關閉驗證頁不久時不立即再彈出（原頁面的重試請求還在用舊的 Cookie）
            if let closed = challengeClosedAt, Date().timeIntervalSince(closed) < 20 { return }
            // 10 分鐘內已彈出 3 次仍無法通過：不再自動彈出，改為提示一次，由使用者決定是否手動開啟
            let now = Date()
            challengeTimes = challengeTimes.filter { now.timeIntervalSince($0) < 600 }
            if challengeTimes.count >= 3 {
                if !showsChallengeHelp { pendingChallengeURL = url; showsChallengeHelp = true }
                return
            }
            challengeTimes.append(now)
            challenge = ChallengePage(url: url)
        }
        .alert("AO3 一直要求人機驗證", isPresented: $showsChallengeHelp) {
            Button("開啟驗證頁") {
                if let url = pendingChallengeURL {
                    challengeTimes = []
                    challenge = ChallengePage(url: url)
                }
            }
            Button("稍後再試", role: .cancel) { challengeClosedAt = Date() }
        } message: {
            Text("驗證多次後仍被攔下，可能是 AO3 暫時加強了防護。請稍後再試，或在「設定 › 內容來源」換用其他鏡像。")
        }
        .sheet(item: $challenge, onDismiss: { challengeClosedAt = Date() }) { page in
            CloudflareChallengeView(url: page.url)
        }
        .fullScreenCover(isPresented: Binding(get: { app.showsOnboarding }, set: { app.showsOnboarding = $0 })) {
            OnboardingView()
        }
        // 個人資料同步：開啟與回到前景時拉取、進入背景時上傳
        .task {
            // 書架離線內容：繼續上次未完成的下載與翻譯
            app.offline.resumePending()
            await app.sync.syncNow()
            await app.librarySync.syncNow()
            await app.checkLocalSubscriptions()
            await app.offline.checkUpdates()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await app.sync.syncNow()
                    await app.librarySync.syncNow()
                    await app.checkLocalSubscriptions()
                    await app.offline.checkUpdates()
                }
            case .background:
                Task {
                    await app.sync.syncNow()
                    await app.librarySync.syncNow()
                }
            default: break
            }
        }
    }
}
