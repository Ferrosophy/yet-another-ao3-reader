import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL

    /// CI 建置時寫入：版本號來自 tag 或 project.yml，建置號為 GitHub Actions run number
    private static let versionString: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()
    /// GitHub Issues 的新回饋網址，預先填入版本與系統資訊（不含帳號或閱讀資料）
    private static let feedbackURL: URL = {
        let system = "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        var components = URLComponents(string: "https://github.com/Ferrosophy/yet-another-ao3-reader/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: "\n\n---\nApp \(versionString) · \(system)")]
        return components.url!
    }()

    @State private var showsClearConfirm = false
    @State private var showsDonate = false
    @State private var showsDebug = false
    @AppStorage(StartTab.storageKey) private var startTab: StartTab = .browse
    @AppStorage(OfflineManager.autoTranslateKey) private var offlineTranslates = true
    @AppStorage(OfflineManager.wifiOnlyKey) private var offlineWiFiOnly = false
    @AppStorage(DownloadFormat.storageKey) private var downloadFormat: DownloadFormat = .epub

    var body: some View {
        List {
            Section("一般") {
                Picker("啟動頁面", selection: $startTab) {
                    ForEach(StartTab.allCases) { Text($0.title).tag($0) }
                }
                NavigationLink {
                    InterfaceLanguageView()
                } label: {
                    LabeledContent("介面語言", value: InterfaceLanguage.all.first { $0.code == InterfaceLanguage.selectedCode }?.name ?? String(localized: "跟隨系統"))
                }
                NavigationLink {
                    SourcesView()
                } label: {
                    LabeledContent("內容來源", value: app.sources.selected.name)
                }
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    LabeledContent("資料同步", value: app.sync.provider.title)
                }
                NavigationLink {
                    ReadingStatsView()
                } label: {
                    LabeledContent("時長管理", value: app.readingTime.reminderEnabled
                        ? String(localized: "每 \(app.readingTime.reminderMinutes) 分鐘提醒") : "")
                }
                Button {
                    app.showsOnboarding = true
                } label: {
                    Text("顯示教程")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // 直接在瀏覽器開啟 GitHub Issues，已附上版本資訊
                // 以一般按鈕外觀呈現（Link 在列表中會套用主題色）
                Button {
                    openURL(Self.feedbackURL)
                } label: {
                    Text("意見回饋")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button {
                    showsDonate = true
                } label: {
                    Text("支持贊助")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // 連續點擊三次進入除錯頁
                LabeledContent("應用版本", value: Self.versionString)
                    .contentShape(.rect)
                    .onTapGesture(count: 3) { showsDebug = true }
            }

            Section("翻譯") {
                NavigationLink {
                    TranslationSettingsView()
                } label: {
                    LabeledContent("翻譯服務", value: app.translation.config.provider.title)
                }
                LabeledContent("目標語言", value: app.translation.config.targetLanguage.name)
            }

            Section("譯文顯示") {
                NavigationLink("瀏覽頁") { TranslationVisibilityView(scope: .browse) }
                NavigationLink("閱讀頁") { TranslationVisibilityView(scope: .reader) }
            }

            Section {
                NavigationLink("批次下載") { BatchDownloadView() }
                NavigationLink {
                    DownloadsView()
                } label: {
                    LabeledContent("下載列表", value: ByteCountFormatter.string(fromByteCount: app.offline.totalSize, countStyle: .file))
                }
                Picker("預設下載格式", selection: $downloadFormat) {
                    ForEach(DownloadFormat.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                Toggle("自動翻譯離線內容", isOn: $offlineTranslates)
                    .onChange(of: offlineTranslates) { app.offline.settingsChanged() }
                Toggle("僅在 Wi-Fi 下載", isOn: $offlineWiFiOnly)
                    .onChange(of: offlineWiFiOnly) { app.offline.settingsChanged() }
            } header: {
                Text("下載")
            } footer: {
                Text("離線保存的作品會下載到 App 內：先下載原文，全部完成後再翻譯。EPUB 為 App 產生的雙語版本，其他格式使用 AO3 官網檔案；匯出檔可在「檔案」App 的 YAAO3R › Bookshelf 中找到。使用付費翻譯 API 時會先詢問；更換目標語言後可在「離線」長按作品「重新翻譯」。")
            }

            Section("外觀") {
                ForEach(AppearanceTab.allCases) { tab in
                    NavigationLink {
                        AppearanceSettingsView(tab: tab)
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                }
            }

            Section {
                Button("清除翻譯快取", role: .destructive) {
                    Task { await app.translator.clearCache() }
                }
                Button("清除所有本地資料", role: .destructive) {
                    showsClearConfirm = true
                }
            } header: {
                Text("隱私")
            }
        }
        .navigationTitle("設定")
        .sheet(isPresented: $showsDonate) { DonateView() }
        .navigationDestination(isPresented: $showsDebug) { DebugView() }
        .confirmationDialog("清除所有本地資料？", isPresented: $showsClearConfirm, titleVisibility: .visible) {
            Button("清除並關閉 App", role: .destructive) {
                Task {
                    await LocalDataEraser.eraseAll()
                    // 各資料儲存仍在記憶體中，關閉 App 避免舊資料再被寫回
                    exit(0)
                }
            }
        } message: {
            Text("將刪除這台裝置上的所有設定、離線作品、書架、閱讀紀錄、翻譯快取、匯入的字體、API Key 與登入狀態，且無法復原。iCloud 或 WebDAV 上的同步資料不受影響。完成後 App 會關閉，請重新開啟。")
        }
    }
}

/// 設定 › 譯文顯示：瀏覽頁或閱讀頁分別決定作品名稱、Fandom、標籤、簡介是否顯示譯文。
struct TranslationVisibilityView: View {
    enum Scope { case browse, reader }
    let scope: Scope

    @AppStorage(TranslationVisibility.titleKey) private var browseTitle = true
    @AppStorage(TranslationVisibility.fandomKey) private var browseFandom = true
    @AppStorage(TranslationVisibility.tagsKey) private var browseTags = true
    @AppStorage(TranslationVisibility.summaryKey) private var browseSummary = true
    @AppStorage(TranslationVisibility.readerTitleKey) private var readerTitle = true
    @AppStorage(TranslationVisibility.readerFandomKey) private var readerFandom = true
    @AppStorage(TranslationVisibility.readerRatingKey) private var readerRating = true
    @AppStorage(TranslationVisibility.readerWarningKey) private var readerWarning = true
    @AppStorage(TranslationVisibility.readerCategoryKey) private var readerCategory = true
    @AppStorage(TranslationVisibility.readerRelationshipKey) private var readerRelationship = true
    @AppStorage(TranslationVisibility.readerCharacterKey) private var readerCharacter = true
    @AppStorage(TranslationVisibility.readerFreeformKey) private var readerFreeform = true
    @AppStorage(TranslationVisibility.readerNotesKey) private var readerNotes = true
    @AppStorage(TranslationVisibility.readerSummaryKey) private var readerSummary = true

    var body: some View {
        Form {
            Section {
                if scope == .browse {
                    Toggle("作品名稱", isOn: $browseTitle)
                    Toggle("原作", isOn: $browseFandom)
                    Toggle("標籤", isOn: $browseTags)
                    Toggle("簡介", isOn: $browseSummary)
                } else {
                    // 依 AO3 作品頁的標籤順序
                    Toggle("作品名稱", isOn: $readerTitle)
                    Toggle("分級", isOn: $readerRating)
                    Toggle("警告", isOn: $readerWarning)
                    Toggle("分類", isOn: $readerCategory)
                    Toggle("原作", isOn: $readerFandom)
                    Toggle("配對", isOn: $readerRelationship)
                    Toggle("角色", isOn: $readerCharacter)
                    Toggle("其他標籤", isOn: $readerFreeform)
                    Toggle("簡介", isOn: $readerSummary)
                    Toggle("作者註", isOn: $readerNotes)
                }
            } footer: {
                if scope == .browse {
                    Text("瀏覽頁的作品卡片與各作品列表。")
                } else {
                    Text("閱讀頁開啟翻譯時，這些內容是否顯示譯文。作品名稱、簡介與作者註譯成翻譯設定的目標語言，原作與各類標籤譯成介面語言。")
                }
            }
        }
        .navigationTitle(scope == .browse ? "瀏覽頁" : "閱讀頁")
    }
}
