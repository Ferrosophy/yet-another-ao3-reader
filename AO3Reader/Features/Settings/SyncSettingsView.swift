import SwiftUI

/// 資料同步：書架與本機使用者資料各自選擇 iCloud 或 WebDAV，WebDAV 伺服器設定兩者共用。
/// AO3 帳號資料直接讀寫 AO3，不經過這裡。
struct SyncSettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage(DataSource.storageKey) private var dataSource: DataSource = .ao3
    @State private var password = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        @Bindable var sync = app.sync
        @Bindable var librarySync = app.librarySync
        let usesICloud = sync.provider == .iCloud || librarySync.provider == .iCloud
        let usesWebDAV = sync.provider == .webDAV || librarySync.provider == .webDAV

        Form {
            Section {
                Picker("同步服務", selection: $sync.provider) {
                    ForEach(SyncProvider.allCases) { Text($0.title).tag($0) }
                }
                if sync.provider != .off {
                    status(isSyncing: sync.isSyncing, lastSyncAt: sync.lastSyncAt, error: sync.lastError) {
                        await sync.syncNow()
                    }
                }
            } header: {
                Text("離線清單同步")
            } footer: {
                Text("同步離線清單（含自訂封面）、閱讀進度、閱讀時長，以及外觀與翻譯偏好。離線檔案由每台裝置自行下載；不包含 API Key、匯入的字體與背景圖片。")
            }

            Section {
                Picker("同步服務", selection: $librarySync.provider) {
                    ForEach(SyncProvider.allCases) { Text($0.title).tag($0) }
                }
                if librarySync.provider != .off, dataSource == .local {
                    status(isSyncing: librarySync.isSyncing, lastSyncAt: librarySync.lastSyncAt, error: librarySync.lastError) {
                        await librarySync.syncNow()
                    }
                }
            } header: {
                Text("本機使用者資料同步")
            } footer: {
                if dataSource == .local {
                    Text("同步本機保存的書籤、稍後閱讀、閱讀紀錄與訂閱。")
                } else {
                    Text("目前使用 AO3 帳號資料，書籤、稍後閱讀、閱讀紀錄、訂閱與收件匣直接讀寫你的 AO3 帳號。在「我的 AO3」切換為本機保存後才會同步。")
                }
            }

            if usesICloud {
                Section {
                    Text("使用你的 iCloud 雲碟保存同步檔。需要在裝置上登入 iCloud 並開啟 iCloud 雲碟；自行簽名時須保留或加入 iCloud Documents 能力（容器為 iCloud.<Bundle ID>），否則無法使用。")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if usesWebDAV {
                Section("WebDAV 伺服器") {
                    TextField("伺服器位址", text: $sync.webDAV.server, prompt: Text(verbatim: "https://dav.jianguoyun.com/dav/"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("帳號", text: $sync.webDAV.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("應用密碼", text: $password)
                        .textContentType(.password)
                        .onSubmit { sync.webDAVPassword = password }
                    TextField("資料夾", text: $sync.webDAV.folder, prompt: Text(verbatim: "AO3Reader"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        sync.webDAVPassword = password
                        test()
                    } label: {
                        HStack {
                            Text("儲存並測試連線")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting)
                    if let testResult {
                        Text(testResult).appFont(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    guideStep(1, "註冊堅果雲", detail: String(localized: "在 jianguoyun.com 註冊並登入，免費提供 WebDAV 空間。"))
                    guideStep(2, "生成應用密碼", detail: String(localized: "帳戶資訊 › 安全選項 › 第三方應用管理 › 添加應用，名稱填 YAAO3R。"))
                    guideStep(3, "填寫上方設定", detail: String(localized: "伺服器位址填 \(Self.jianguoyunURL)，帳號是堅果雲的登入信箱，密碼是剛生成的應用密碼。"))
                    guideStep(4, "測試並同步", detail: String(localized: "點「儲存並測試連線」，成功後點「立即同步」。"))
                } header: {
                    Text("如何使用 WebDAV 同步")
                } footer: {
                    Text("其他裝置填入相同設定即可同步。也可使用 Nextcloud、群暉 NAS 等任何 WebDAV 服務。")
                }
            }
        }
        .navigationTitle("資料同步")
        .onAppear { password = app.sync.webDAVPassword }
    }

    @ViewBuilder
    private func status(isSyncing: Bool, lastSyncAt: Date?, error: String?, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Text("立即同步")
                Spacer()
                if isSyncing { ProgressView() }
            }
        }
        .disabled(isSyncing)
        if let lastSyncAt {
            LabeledContent("上次同步", value: lastSyncAt.formatted(date: .abbreviated, time: .shortened))
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .appFont(.footnote)
                .foregroundStyle(.red)
        }
    }

    private static let jianguoyunURL = "https://dav.jianguoyun.com/dav/"

    /// detail 以純文字顯示（不解析 Markdown，網址不會變成連結）
    private func guideStep(_ number: Int, _ title: LocalizedStringKey, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .appFont(.caption, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.tint, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appFont(.subheadline, weight: .semibold)
                Text(detail)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func test() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            do {
                try await app.sync.testWebDAV()
                testResult = String(localized: "連線成功")
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}
