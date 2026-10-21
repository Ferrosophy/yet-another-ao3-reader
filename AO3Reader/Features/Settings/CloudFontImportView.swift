// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import WebKit

/// 可匯入字體的雲端硬碟。在網頁中登入並下載 TTF / OTF 檔即自動匯入。
enum CloudDrive: String, CaseIterable, Identifiable {
    case googleDrive, baidu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .googleDrive: "Google Drive"
        case .baidu: String(localized: "百度網盤")
        }
    }

    var url: URL {
        switch self {
        case .googleDrive: URL(string: "https://drive.google.com/drive/my-drive")!
        case .baidu: URL(string: "https://pan.baidu.com/")!
        }
    }
}

/// 以網頁開啟雲端硬碟，攔截字體檔的下載並匯入為閱讀字體。
struct CloudFontImportView: View {
    let drive: CloudDrive
    var onImported: (CustomFont) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var isDownloading = false

    var body: some View {
        NavigationStack {
            FontDownloadWebView(url: drive.url) { event in
                switch event {
                case .started:
                    isDownloading = true
                    status = String(localized: "正在下載字體…")
                case .finished(let file):
                    isDownloading = false
                    do {
                        let font = try app.appearance.importFont(from: file)
                        onImported(font)
                        dismiss()
                    } catch {
                        status = error.localizedDescription
                    }
                case .failed(let message):
                    isDownloading = false
                    status = message
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(drive.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    if isDownloading { ProgressView().controlSize(.small) }
                    Text(status ?? String(localized: "登入後找到字體檔（.ttf / .otf）並點擊下載，下載完成會自動匯入。"))
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }
}

/// 雲端硬碟網頁：一般導覽照常顯示；回應為字體檔或被要求下載時改用 WKDownload 存到暫存目錄。
struct FontDownloadWebView: UIViewRepresentable {
    enum Event {
        case started
        case finished(URL)
        case failed(String)
    }

    let url: URL
    var onEvent: (Event) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = AO3Client.userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var onEvent: (Event) -> Void
        private var destinations: [ObjectIdentifier: URL] = [:]

        init(onEvent: @escaping (Event) -> Void) {
            self.onEvent = onEvent
        }

        private static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

        private static func isFont(_ response: URLResponse) -> Bool {
            let name = (response.suggestedFilename ?? response.url?.lastPathComponent ?? "").lowercased()
            let ext = (name as NSString).pathExtension
            let mime = response.mimeType?.lowercased() ?? ""
            return fontExtensions.contains(ext) || mime.hasPrefix("font/") || mime.contains("truetype") || mime.contains("opentype")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.shouldPerformDownload ? .download : .allow
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if Self.isFont(navigationResponse.response) || !navigationResponse.canShowMIMEType { return .download }
            return .allow
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
            onEvent(.started)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
            onEvent(.started)
        }

        /// 網頁以新視窗開啟下載連結時，在同一個視窗載入
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String) async -> URL? {
            let directory = FileManager.default.temporaryDirectory.appending(path: "FontDownloads", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appending(path: suggestedFilename.isEmpty ? "font.ttf" : suggestedFilename)
            try? FileManager.default.removeItem(at: file)
            destinations[ObjectIdentifier(download)] = file
            return file
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let file = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            let ext = file.pathExtension.lowercased()
            if Self.fontExtensions.contains(ext) {
                onEvent(.finished(file))
            } else {
                onEvent(.failed(String(localized: "下載的檔案不是字體（.ttf / .otf）")))
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            destinations.removeValue(forKey: ObjectIdentifier(download))
            onEvent(.failed(error.localizedDescription))
        }
    }
}
