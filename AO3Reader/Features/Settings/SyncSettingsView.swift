import SwiftUI

/// 資料同步：AO3 帳號同步與個人資料同步（iCloud / WebDAV）分開，兩邊的資料互不重疊。
struct SyncSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var password = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        @Bindable var sync = app.sync

        Form {
            Section {
                LabeledContent("AO3 帳號", value: app.auth.username ?? String(localized: "未登入"))
            } header: {
                Text("AO3 帳號同步")
            } footer: {
                Text("書籤、稍後閱讀、閱讀紀錄、訂閱與收件匣直接讀寫你的 AO3 帳號，登入後自動同步，不經過任何第三方服務。")
            }

            Section {
                Picker("同步服務", selection: $sync.provider) {
                    ForEach(SyncProvider.allCases) { Text($0.title).tag($0) }
                }
                if sync.provider != .off {
                    Button {
                        Task { await sync.syncNow() }
                    } label: {
                        HStack {
                            Text("立即同步")
                            Spacer()
                            if sync.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(sync.isSyncing)
                    if let last = sync.lastSyncAt {
                        LabeledContent("上次同步", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let error = sync.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .appFont(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("個人資料同步")
            } footer: {
                Text("同步書架（含自訂封面）、閱讀時長、閱讀進度，以及外觀與翻譯偏好。不包含 API Key、匯入的字體與背景圖片。這些資料與 AO3 帳號資料分開保存，不會互相覆蓋。")
            }

            if sync.provider == .iCloud {
                Section {
                    Text("使用你的 iCloud 雲碟保存同步檔。需要在裝置上登入 iCloud 並開啟 iCloud 雲碟；自行簽名時須保留或加入 iCloud Documents 能力（容器為 iCloud.<Bundle ID>），否則無法使用。")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if sync.provider == .webDAV {
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
                    VStack(alignment: .leading, spacing: 10) {
                        guideStep(1, "註冊並登入堅果雲網頁版（jianguoyun.com）。堅果雲提供免費的 WebDAV 空間，國內外都能穩定連線，推薦作為同步服務。")
                        guideStep(2, "點右上角帳號名稱 →「帳戶資訊」→「安全選項」，在「第三方應用管理」中點「添加應用」，名稱填 YAAO3R，然後「生成密碼」。")
                        guideStep(3, "伺服器位址填 https://dav.jianguoyun.com/dav/，帳號填堅果雲的登入信箱，應用密碼填剛才生成的密碼（不是登入密碼）。")
                        guideStep(4, "資料夾可保留 AO3Reader，App 會自動建立。點「儲存並測試連線」，成功後點「立即同步」。")
                        guideStep(5, "在其他裝置上填入相同設定即可同步。也可使用 Nextcloud、群暉 NAS 等任何 WebDAV 服務。")
                    }
                    .appFont(.footnote)
                    .padding(.vertical, 4)
                } header: {
                    Text("如何使用 WebDAV 同步（推薦堅果雲）")
                }
            }
        }
        .navigationTitle("資料同步")
        .onAppear { password = app.sync.webDAVPassword }
    }

    private func guideStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(number)")
                .appFont(.caption, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.tint, in: .circle)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func test() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            do {
                try await app.sync.testConnection()
                testResult = String(localized: "連線成功")
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}
