// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import WebKit

/// 要在 App 內網頁打開的網址
struct WebTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// 在 App 內打開來源網站上的作品頁：帶入 App 的 Cookie（登入狀態與人機驗證）與相同的 User-Agent。
struct WebPageSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            SourceWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host() ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { dismiss() }
                    }
                    if url.host() != DemoSite.host {
                        ToolbarItem(placement: .primaryAction) {
                            Button("在 Safari 開啟", systemImage: "safari") { openURL(url) }
                        }
                    }
                }
        }
    }
}

private struct SourceWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.customUserAgent = AO3Client.userAgent
        webView.allowsBackForwardNavigationGestures = true
        // 展示模式沒有真實網頁
        if url.host() == DemoSite.host {
            webView.loadHTMLString(Self.demoPage, baseURL: nil)
            return webView
        }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let url = url
        Task { @MainActor in
            for cookie in cookies { await store.setCookie(cookie) }
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private static let demoPage = """
    <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
    <body style="font-family:-apple-system;padding:32px;color:#888;text-align:center">
    <h3>Demo</h3><p>This is a fictional demo work. There is no real web page.</p></body></html>
    """
}
