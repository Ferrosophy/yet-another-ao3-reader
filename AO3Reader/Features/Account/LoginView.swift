// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import WebKit

/// 原生登入表單；若來源啟用了 Cloudflare 驗證或原生登入失敗，可改用網頁登入。
struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var showsWebLogin = false
    /// 使用鏡像登入時，需先確認了解風險
    @State private var acceptsMirrorRisk = false

    private var isMirror: Bool { app.sources.selected.id != AO3Source.official.id }
    private var canLogin: Bool { !isMirror || acceptsMirrorRisk }
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .padding(28)
                    .glassEffect(.regular, in: .circle)
                    .padding(.top, 32)

                VStack(spacing: 4) {
                    Text("登入 Archive of Our Own").appFont(.title2, weight: .bold)
                    Text(app.sources.selected.baseURL.host() ?? "")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    TextField("用戶名或電子郵件", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("密碼", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(login)
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

                if isMirror {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("你正在透過鏡像站登入", systemImage: "exclamationmark.shield.fill")
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.orange)
                        Text("鏡像站不是 AO3 官方網站。鏡像的營運者能看到你輸入的帳號與密碼，以及登入後帳號裡的內容。App 的「測試連線」只檢查頁面格式是否相容，不代表這個鏡像安全可信。建議盡量在官網登入；若一定要使用鏡像，請只使用你信任的鏡像，並避免使用與其他網站相同的密碼。")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle("我了解風險，仍要登入", isOn: $acceptsMirrorRisk)
                            .appFont(.footnote)
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 16))
                }

                if let error {
                    Text(error)
                        .appFont(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: login) {
                    Group {
                        if app.auth.isWorking { ProgressView() } else { Text("登入") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(username.isEmpty || password.isEmpty || app.auth.isWorking || !canLogin)

                Button("使用網頁登入") { showsWebLogin = true }
                    .buttonStyle(.glass)
                    .disabled(!canLogin)

                Text("密碼只會直接傳送給目前的 AO3 來源，不會被本應用保存。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showsWebLogin) {
            NavigationStack {
                WebLoginView(url: app.client.url("/users/login")) {
                    showsWebLogin = false
                    Task { await app.auth.refresh(client: app.client) }
                }
                .navigationTitle("網頁登入")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") {
                            showsWebLogin = false
                            Task { await app.auth.refresh(client: app.client) }
                        }
                    }
                }
            }
        }
    }

    private func login() {
        guard !username.isEmpty, !password.isEmpty, canLogin else { return }
        error = nil
        Task {
            do {
                try await app.auth.login(username: username, password: password, client: app.client)
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// WKWebView 登入，用於通過 Cloudflare 驗證或處理原生表單無法處理的情況。
/// 每次頁面載入完成都把 WebView 的 cookie 同步到 `HTTPCookieStorage.shared`，
/// 偵測到已登入（頁首出現用戶名）時自動關閉。
struct WebLoginView: UIViewRepresentable {
    let url: URL
    var onLoggedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(host: url.host(), onLoggedIn: onLoggedIn) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = AO3Client.userAgent
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let host: String?
        let onLoggedIn: () -> Void
        init(host: String?, onLoggedIn: @escaping () -> Void) {
            self.host = host
            self.onLoggedIn = onLoggedIn
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                // 只同步登入網站的 Cookie
                for cookie in cookies where cookie.belongs(to: host) {
                    HTTPCookieStorage.shared.setCookie(cookie.forURLSession ?? cookie)
                }
                let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
                if let html, AO3Parser.loggedInUsername(html) != nil {
                    onLoggedIn()
                }
            }
        }
    }
}
