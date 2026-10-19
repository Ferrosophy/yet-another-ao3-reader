import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    /// CI 建置時寫入：版本號來自 tag 或 project.yml，建置號為 GitHub Actions run number
    private static let versionString: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()
    @State private var showsClearConfirm = false

    var body: some View {
        List {
            Section("內容來源") {
                NavigationLink {
                    SourcesView()
                } label: {
                    LabeledContent("目前來源", value: app.sources.selected.name)
                }
            }

            Section("外觀") {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    LabeledContent("深色模式、主題色、閱讀背景與字體", value: app.appearance.config.colorScheme.title)
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
                Button("清除翻譯快取") {
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

            Section {
                LabeledContent("版本", value: Self.versionString)
            }
        }
        .navigationTitle("設定")
        .confirmationDialog("刪除所有 API Key？", isPresented: $showsClearConfirm, titleVisibility: .visible) {
            Button("刪除", role: .destructive) { KeychainStore.deleteAll() }
        }
    }
}
