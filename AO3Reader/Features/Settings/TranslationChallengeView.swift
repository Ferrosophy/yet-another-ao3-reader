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
    /// 指定時，網頁通過驗證、且 App 的請求也不再被攔下時呼叫（Cookie 已同步完成）
    var onPassed: (() -> Void)?
    /// 網頁已通過驗證，但 App 的請求仍被攔下時呼叫
    var onBlocked: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onPassed: onPassed, onBlocked: onBlocked) }

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
        private let url: URL
        private let onPassed: (() -> Void)?
        private let onBlocked: (() -> Void)?
        private var passed = false
        private var checking = false

        init(url: URL, onPassed: (() -> Void)?, onBlocked: (() -> Void)?) {
            self.url = url
            self.onPassed = onPassed
            self.onBlocked = onBlocked
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                await syncCookiesNow(from: webView)
                guard onPassed != nil, !passed, !checking else { return }
                // 驗證頁可能在通過前重新載入好幾次，等頁面穩定後再判斷
                try? await Task.sleep(for: .milliseconds(800))
                guard !webView.isLoading, !passed, !checking else { return }
                guard await Self.looksPassed(webView) else {
                    await log(webView, summary: "Verification page: still challenging")
                    return
                }
                // 網頁看起來已通過：同步 Cookie 後由 App 實際請求一次，App 也能取得頁面才算通過
                checking = true
                defer { checking = false }
                await syncCookiesNow(from: webView)
                let ok = await AO3Client.verifyAccess(url)
                await log(webView, summary: ok ? "Verification page: passed" : "Verification page: passed in web, app request still blocked")
                if ok {
                    passed = true
                    onPassed?()
                } else {
                    onBlocked?()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DebugLog.record(DebugEntry(kind: .verify, url: webView.url?.absoluteString ?? "", summary: "Verification page failed: \(error.localizedDescription)"))
        }

        /// 除錯紀錄：驗證頁目前的網址、標題，以及網頁與 App 兩邊的 Cookie 名稱（用來確認 Cookie 是否同步成功）
        private func log(_ webView: WKWebView, summary: String) async {
            let title = (try? await webView.evaluateJavaScript("document.title") as? String) ?? ""
            let languages = (try? await webView.evaluateJavaScript("navigator.languages.join(',')") as? String) ?? ""
            let html = (try? await webView.evaluateJavaScript("document.documentElement.outerHTML.slice(0, 1500)") as? String) ?? ""
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                .filter { webView.url?.host()?.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) ?? false }
            let appCookies = (HTTPCookieStorage.shared.cookies(for: url) ?? []).map(\.name).sorted()
            let detail = [
                "Title: \(title)",
                "navigator.languages: \(languages)",
                "App Accept-Language: \(AO3Client.acceptLanguage)",
                "Web cookies: \(cookies.map(\.name).sorted().joined(separator: ", "))",
                "Web cookie attributes: \(cookies.map(Self.describe).sorted().joined(separator: ", "))",
                "App cookies for \(url.host() ?? ""): \(appCookies.joined(separator: ", "))",
                "— Page (first 1500 chars) —",
                html,
            ].joined(separator: "\n")
            DebugLog.record(DebugEntry(kind: .verify, url: webView.url?.absoluteString ?? "", summary: summary, detail: detail))
        }

        private static func describe(_ cookie: HTTPCookie) -> String {
            var flags = [cookie.domain + cookie.path]
            if cookie.isSecure { flags.append("secure") }
            if cookie.isHTTPOnly { flags.append("httpOnly") }
            if let policy = cookie.sameSitePolicy { flags.append(policy.rawValue) }
            return "\(cookie.name)[\(flags.joined(separator: " "))]"
        }

        /// 頁面看起來已不是驗證頁：沒有 Cloudflare / Anubis 的驗證元素與「Just a moment」標題，或已出現 AO3 的頁面結構。
        /// 最終是否通過由 `AO3Client.verifyAccess` 實際請求判斷，這裡只決定何時去檢查。
        private static func looksPassed(_ webView: WKWebView) async -> Bool {
            let script = """
            (function() {
              if (document.querySelector('#outer #main, #outer #header')) return true;
              var challenge = !!document.querySelector('#challenge-form, #challenge-stage, #challenge-running, #challenge-error-text, #anubis_challenge')
                || /^just a moment/i.test(document.title);
              return !challenge && document.readyState === 'complete';
            })()
            """
            return (try? await webView.evaluateJavaScript(script) as? Bool) == true
        }

        func syncCookies(from webView: WKWebView) {
            Task { await syncCookiesNow(from: webView) }
        }

        private func syncCookiesNow(from webView: WKWebView) async {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in await store.allCookies() {
                HTTPCookieStorage.shared.setCookie(cookie.forURLSession ?? cookie)
            }
        }
    }
}

/// AO3 請求被 Cloudflare 攔下時彈出的人機驗證頁。通過後自動關閉，回到原頁面重試即可。
struct CloudflareChallengeView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    /// 網頁已通過但 App 的請求仍被攔下
    @State private var blocked = false

    var body: some View {
        NavigationStack {
            VerificationWebView(url: url, onPassed: {
                // 稍等一下讓 Cookie 寫入後再關閉
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                }
            }, onBlocked: {
                blocked = true
            })
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("人機驗證")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Group {
                    if blocked {
                        Label("網頁已通過驗證，但這個鏡像仍拒絕 App 的請求，可能不支援在 App 中使用。請稍後再試，或在「設定 › 內容來源」換用其他鏡像。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("網站的防護（Cloudflare 或 Anubis）要求確認你不是機器人。請點擊頁面中的驗證方塊，或等待自動驗證完成；通過後會自動關閉，再重新整理原頁面即可。")
                            .foregroundStyle(.secondary)
                    }
                }
                .appFont(.footnote)
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
