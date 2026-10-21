// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 新手引導：第一次開啟時顯示，之後可在「設定 › 顯示教程」重看。
/// 重點是連線檢測：連不上目前的來源（例如在中國大陸連 AO3 官網）時，引導使用者加入鏡像源。
/// 本 App 不內建任何鏡像網址。
struct OnboardingView: View {
    @Environment(AppState.self) private var app

    private enum Step: Int, CaseIterable {
        case welcome, connection, translation, done
    }

    @State private var step: Step = .welcome
    @State private var connection: ConnectionState = .idle
    /// 曾經連不上來源（即使之後加入了鏡像）：推薦在中國大陸可用的翻譯服務
    @State private var needsMirror = false
    @State private var adjustedProvider = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: WelcomePage()
                case .connection: ConnectionPage(state: $connection, needsMirror: $needsMirror)
                case .translation: TranslationPage(unreachable: needsMirror)
                case .done: DonePage()
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("上一步", systemImage: "chevron.backward") { move(-1) }
                    }
                }
                if step != .done {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("跳過") { finish() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(.tint)
                        .opacity(item == step ? 1 : 0.3)
                        .frame(width: item == step ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: step)
            .accessibilityHidden(true)
            Button {
                step == .done ? finish() : move(1)
            } label: {
                Text(step == .done ? LocalizedStringKey("開始使用") : LocalizedStringKey("下一步"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        // 連不上來源時，預設的 Google 翻譯多半也無法使用：改為推薦的騰訊翻譯（使用者可再改）
        if next == .translation, needsMirror, !adjustedProvider,
           app.translation.config.provider == .googleWeb {
            app.translation.config.provider = .transmart
            adjustedProvider = true
        }
        withAnimation(.snappy) { step = next }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: AppState.onboardingKey)
        app.showsOnboarding = false
    }
}

/// 連線檢測的結果
enum ConnectionState: Equatable {
    case idle, testing, reachable, unreachable
}

// MARK: - Pages

/// 每頁頂部的大圖示與標題
private struct PageHeader: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 84, height: 84)
                .glassEffect(.regular, in: .circle)
            Text(title)
                .appFont(.title2)
                .bold()
                .multilineTextAlignment(.center)
            Text(message)
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }
}

private struct WelcomePage: View {
    var body: some View {
        List {
            PageHeader(systemImage: "books.vertical.fill",
                       title: "歡迎使用 YAAO3R",
                       message: "Yet another AO3 reader：瀏覽、搜尋與離線保存 AO3 作品，並以原文與譯文對照閱讀。")
            Section {
                Label("瀏覽最新作品，搜尋作品、標籤、作者與合集", systemImage: "sparkles.rectangle.stack")
                Label("沉浸式翻譯：譯文顯示在每段原文下方", systemImage: "character.book.closed")
                Label("離線保存：先下載原文再翻譯，沒有網路也能讀", systemImage: "arrow.down.circle")
                Label("登入 AO3 帳號，或把書籤與紀錄保存在本機", systemImage: "person.crop.circle")
            } footer: {
                Text("本 App 為非官方的第三方客戶端，與 AO3 及 OTW 無關。")
            }
        }
    }
}

private struct ConnectionPage: View {
    @Environment(AppState.self) private var app
    @Binding var state: ConnectionState
    /// 曾經連不上時展開「加入鏡像源」，之後保持顯示
    @Binding var needsMirror: Bool

    @State private var urlText = ""
    @State private var mirrorStatus: MirrorStatus = .idle

    private enum MirrorStatus: Equatable {
        case idle, testing, ok, needsVerification, failed(String)
    }

    var body: some View {
        List {
            PageHeader(systemImage: "network",
                       title: "連線檢測",
                       message: "確認能否連上目前的內容來源。")
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.sources.selected.name)
                        Text(app.sources.selected.baseURL.absoluteString)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch state {
                    case .idle, .testing: ProgressView()
                    case .reachable: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .unreachable: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
                Button("重新檢測") { Task { await test() } }
                    .disabled(state == .testing)
            } header: {
                Text("目前的來源")
            } footer: {
                switch state {
                case .reachable: Text("可以正常連線。若之後無法連線，可在「設定 › 內容來源」加入鏡像源。")
                case .unreachable: Text("無法連上這個來源。")
                default: EmptyView()
                }
            }

            if state == .unreachable || needsMirror {
                mirrorSection
            }
        }
        .task {
            if state == .idle { await test() }
        }
    }

    @ViewBuilder
    private var mirrorSection: some View {
        Section {
            Text("在中國大陸等地區通常無法直接連上 AO3 官網，需要加入「鏡像源」：內容與 AO3 相同、可以直接連線的網站。本 App 不提供鏡像網址，請自行尋找可信的 AO3 鏡像，把網址貼到下方。")
                .appFont(.callout)
            TextField("網址，例如 https://mirror.example.org", text: $urlText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: urlText) { mirrorStatus = .idle }
            Button("測試並使用這個鏡像") { Task { await addMirror() } }
                .disabled(SourceStore.normalize(urlText) == nil || mirrorStatus == .testing)
            switch mirrorStatus {
            case .idle: EmptyView()
            case .testing: ProgressView()
            case .ok:
                Label("已加入並切換到這個鏡像", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            case .needsVerification:
                Label("已加入並切換到這個鏡像。它需要人機驗證，開始瀏覽時會彈出驗證頁，照畫面完成即可。", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        } header: {
            Text("加入鏡像源")
        } footer: {
            Text("登入時密碼會傳送給鏡像站，請只使用你信任的鏡像。之後可在「設定 › 內容來源」管理或切換。")
        }
    }

    private func test() async {
        state = .testing
        let result = await ConnectionProbe.check(app.sources.selected.baseURL)
        state = result == .unreachable ? .unreachable : .reachable
        if state == .unreachable { needsMirror = true }
    }

    private func addMirror() async {
        guard let url = SourceStore.normalize(urlText) else { return }
        mirrorStatus = .testing
        let result = await ConnectionProbe.check(url)
        switch result {
        case .unreachable:
            mirrorStatus = .failed(String(localized: "無法連上這個網址"))
        case .notAO3:
            mirrorStatus = .failed(String(localized: "回應不像 AO3 頁面，可能不是相容的鏡像"))
        case .ao3, .challenge:
            let source = app.sources.add(name: "", url: url)
            await app.selectSource(source)
            mirrorStatus = result == .challenge ? .needsVerification : .ok
            state = .reachable
        }
    }
}

private struct TranslationPage: View {
    @Environment(AppState.self) private var app
    let unreachable: Bool

    var body: some View {
        @Bindable var settings = app.translation
        let options = TranslationProviderKind.allCases.filter { !$0.requiresAPIKey || $0 == settings.config.provider }
        List {
            PageHeader(systemImage: "character.bubble",
                       title: "翻譯",
                       message: "選擇翻譯服務與目標語言，之後都可以在「設定 › 翻譯」更改。")
            Section {
                LanguageListRow(title: "目標語言", languages: TranslationLanguage.all,
                                selection: Binding(get: { Optional(settings.config.targetLanguageCode) },
                                                   set: { if let code = $0 { settings.config.targetLanguageCode = code } }))
            }
            Section {
                Picker("翻譯服務", selection: $settings.config.provider) {
                    ForEach(options) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("翻譯服務")
            } footer: {
                if unreachable {
                    Text("Google 翻譯在中國大陸通常無法使用，建議選擇騰訊、火山或 Bing 翻譯。需要 API Key 的服務（例如 AI 翻譯）可稍後在設定中填寫。")
                } else {
                    Text("需要 API Key 的服務（例如 AI 翻譯）可稍後在設定中填寫。")
                }
            }
        }
    }
}

private struct DonePage: View {
    var body: some View {
        List {
            PageHeader(systemImage: "checkmark.circle.fill",
                       title: "準備好了",
                       message: "以下是幾個小提示。")
            Section {
                Label("把作品加入「離線」後會自動下載並翻譯，沒有網路也能閱讀", systemImage: "arrow.down.circle")
                Label("在「帳號」登入 AO3，或選擇「本機保存」記錄書籤與閱讀紀錄", systemImage: "person.crop.circle")
                Label("遇到人機驗證時，照彈出的頁面完成即可", systemImage: "checkmark.shield")
                Label("介面語言、外觀與字體可在「設定」調整", systemImage: "gearshape")
            } footer: {
                Text("隨時可以在「設定 › 顯示教程」重新查看本引導。")
            }
        }
    }
}

// MARK: - Probe

/// 新手引導的連線檢測：使用短逾時、不經過 `AO3Client`（不會彈出驗證頁）。
enum ConnectionProbe {
    enum Result: Equatable, Sendable {
        /// 連不上（逾時、DNS 或連線被重設）
        case unreachable
        /// 連得上，但要求人機驗證（Cloudflare / Anubis）
        case challenge
        /// 連得上，而且是 AO3 頁面
        case ao3
        /// 連得上，但不是 AO3 頁面
        case notAO3
    }

    nonisolated static func check(_ baseURL: URL) async -> Result {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpAdditionalHeaders = [
            "User-Agent": AO3Client.userAgent,
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": AO3Client.acceptLanguage,
        ]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(from: baseURL)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            if AO3Client.isCloudflareChallenge(http, data: data) || AO3Client.isAnubisChallenge(data: data) { return .challenge }
            return AO3Parser.looksLikeAO3(String(decoding: data, as: UTF8.self)) ? .ao3 : .notAO3
        } catch {
            DebugLog.record(DebugEntry(kind: .network, url: baseURL.absoluteString,
                                       summary: "Onboarding connection test: \(error.localizedDescription)"))
            return .unreachable
        }
    }
}
