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
        var components = URLComponents(string: "https://github.com/Ferrosophy/AO3-ios-translator/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: "\n\n---\nApp \(versionString) · \(system)")]
        return components.url!
    }()

    @State private var showsClearConfirm = false
    @AppStorage(StartTab.storageKey) private var startTab: StartTab = .browse
    @AppStorage(DownloadFormat.storageKey) private var downloadFormat: DownloadFormat = .epub
    @AppStorage(TranslationVisibility.titleKey) private var showsTitleTranslation = true
    @AppStorage(TranslationVisibility.fandomKey) private var showsFandomTranslation = true
    @AppStorage(TranslationVisibility.tagsKey) private var showsTagTranslation = true
    @AppStorage(TranslationVisibility.summaryKey) private var showsSummaryTranslation = true

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
                LabeledContent("應用版本", value: Self.versionString)
            }

            Section {
                Toggle("作品名稱", isOn: $showsTitleTranslation)
                Toggle("Fandom", isOn: $showsFandomTranslation)
                Toggle("標籤", isOn: $showsTagTranslation)
                Toggle("簡介", isOn: $showsSummaryTranslation)
            } header: {
                Text("顯示譯文")
            } footer: {
                Text("決定作品列表與閱讀頁是否顯示這些內容的譯文。作品名稱與簡介譯成翻譯設定的目標語言，Fandom 與標籤譯成介面語言。")
            }

            Section("下載") {
                NavigationLink("批次下載") { BatchDownloadView() }
                NavigationLink("下載列表") { DownloadsView() }
                Picker("預設下載格式", selection: $downloadFormat) {
                    ForEach(DownloadFormat.allCases) { Text(verbatim: $0.title).tag($0) }
                }
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

            Section("翻譯") {
                NavigationLink {
                    TranslationSettingsView()
                } label: {
                    LabeledContent("翻譯服務", value: app.translation.config.provider.title)
                }
                LabeledContent("目標語言", value: app.translation.config.targetLanguage.name)
            }

            Section {
                Button("清除翻譯快取", role: .destructive) {
                    Task { await app.translator.clearCache() }
                }
                Button("刪除所有已保存的 API Key", role: .destructive) {
                    showsClearConfirm = true
                }
            } header: {
                Text("隱私")
            } footer: {
                Text("""
                本應用沒有帳號系統，也沒有自己的伺服器。API Key 只保存在這台裝置的鑰匙圈中\
                （不經 iCloud 同步、不隨備份轉移），僅在翻譯時直接傳送給你所選的服務商。
                """)
            }
        }
        .navigationTitle("設定")
        .confirmationDialog("刪除所有 API Key？", isPresented: $showsClearConfirm, titleVisibility: .visible) {
            Button("刪除", role: .destructive) { KeychainStore.deleteAll() }
        }
    }
}
