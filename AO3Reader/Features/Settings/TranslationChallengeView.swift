import SwiftUI
import WebKit

/// 翻譯服務要求驗證時彈出的視窗：網頁驗證（驗證碼、安全檢查）或 Apple 翻譯語言下載。
/// 關閉視窗後由呼叫端重試翻譯。
struct TranslationChallengeView: View {
    let challenge: TranslationChallenge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch challenge {
        case .web(let provider, let url):
            NavigationStack {
                VerificationWebView(url: url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(provider)
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .top) {
                        Text("請在網頁中完成驗證（如驗證碼），完成後點「完成」重新翻譯。")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { dismiss() }
                        }
                    }
            }
        case .appleDownload(let source, let target):
            AppleLanguageDownloadView(source: source, target: target) { dismiss() }
                .presentationDetents([.medium])
        }
    }
}

/// 驗證用 WKWebView：使用與翻譯請求相同的 User-Agent，並把網頁 Cookie 同步到 App 的網路層，
/// 讓驗證通過後的 Cookie 在後續翻譯請求中生效。
struct VerificationWebView: UIViewRepresentable {
    let url: URL
    /// 指定時，頁面載入完成且不再是 Cloudflare 驗證頁就呼叫（Cookie 已同步完成）
    var onPassed: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onPassed: onPassed) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.customUserAgent = AO3Client.userAgent
        webView.navigationDelegate = context.coordinator
        // 先把 App 已有的 Cookie 帶進網頁，避免重複驗證
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        Task { @MainActor in
            for cookie in cookies { await store.setCookie(cookie) }
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.syncCookies(from: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onPassed: (() -> Void)?
        private var passed = false

        init(onPassed: (() -> Void)?) {
            self.onPassed = onPassed
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                await syncCookiesNow(from: webView)
                guard let onPassed, !passed else { return }
                let title = (try? await webView.evaluateJavaScript("document.title") as? String) ?? ""
                let isChallenge = ["Just a moment", "Attention Required", "請稍候", "请稍候", "しばらくお待ち"]
                    .contains { title.localizedCaseInsensitiveContains($0) }
                if !isChallenge, !title.isEmpty {
                    passed = true
                    onPassed()
                }
            }
        }

        func syncCookies(from webView: WKWebView) {
            Task { await syncCookiesNow(from: webView) }
        }

        private func syncCookiesNow(from webView: WKWebView) async {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in await store.allCookies() { HTTPCookieStorage.shared.setCookie(cookie) }
        }
    }
}

/// AO3 請求被 Cloudflare 攔下時彈出的人機驗證頁。通過後自動關閉，回到原頁面重試即可。
struct CloudflareChallengeView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VerificationWebView(url: url) {
                // 稍等一下讓 Cookie 寫入後再關閉
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    dismiss()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("人機驗證")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Text("AO3 的 Cloudflare 防護要求確認你不是機器人。請點擊頁面中的驗證方塊，通過後會自動關閉，再重新整理原頁面即可。")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
