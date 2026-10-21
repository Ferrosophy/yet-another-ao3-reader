// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

/// 官網支援的下載格式。
enum DownloadFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case epub, azw3, mobi, pdf, html

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    /// 設定中的預設下載格式
    static let storageKey = "download.format"
}

extension AO3Client {
    /// 下載作品檔案（使用同一個 Cookie，限登入用戶的作品也能下載），預設存到「檔案」App 可見的 Downloads 資料夾。
    func downloadWork(id: Int, title: String, format: DownloadFormat, href: String?,
                      directory: URL? = nil, fileName: String? = nil) async throws -> URL {
        let path = href ?? "/downloads/\(id)/work.\(format.rawValue)"
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw AO3Error.invalidSource }
        let (data, response) = try await Self.longSession.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), !data.isEmpty else { throw AO3Error.http(status) }

        let directory = directory ?? URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: fileName ?? "\(Self.fileName(title)).\(format.rawValue)")
        try data.write(to: file, options: .atomic)
        return file
    }

    /// 移除檔名中不允許的字元
    static func fileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.newlines).union(.controlCharacters)
        let cleaned = title.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "work" : String(cleaned.prefix(120))
    }
}

struct DownloadedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// 系統分享選單（可存到「檔案」、傳到 Kindle / Books 等）。
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 閱讀頁停用「從左向右滑動返回」（含 iOS 26 的全頁滑動返回），只能用導覽列的返回按鈕離開，
/// 避免與翻頁、滑動閱讀衝突。離開閱讀頁時恢復。
struct SwipeBackDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setSwipeBack(enabled: false)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setSwipeBack(enabled: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setSwipeBack(enabled: true)
        }

        private func setSwipeBack(enabled: Bool) {
            guard let navigation = navigationController else { return }
            navigation.interactivePopGestureRecognizer?.isEnabled = enabled
            navigation.interactiveContentPopGestureRecognizer?.isEnabled = enabled
        }
    }
}

/// 放在 SwiftUI ScrollView 內容中，找到底層的 UIScrollView 並停用依安全區域自動調整內距，
/// 讓導覽列或狀態列顯示 / 隱藏時內容不會移動。
struct ScrollInsetLock: UIViewRepresentable {
    func makeUIView(context: Context) -> LockView { LockView() }
    func updateUIView(_ view: LockView, context: Context) { view.apply() }

    final class LockView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    if scrollView.contentInsetAdjustmentBehavior != .never {
                        scrollView.contentInsetAdjustmentBehavior = .never
                        scrollView.automaticallyAdjustsScrollIndicatorInsets = false
                    }
                    return
                }
                view = current.superview
            }
        }
    }
}
