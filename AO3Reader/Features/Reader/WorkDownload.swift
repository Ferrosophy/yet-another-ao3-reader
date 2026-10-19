import SwiftUI
import UIKit

/// 官網支援的下載格式。
enum DownloadFormat: String, CaseIterable, Identifiable, Sendable {
    case epub, azw3, mobi, pdf, html

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    /// 設定中的預設下載格式
    static let storageKey = "download.format"
}

extension AO3Client {
    /// 下載作品檔案（使用同一個 Cookie，限登入用戶的作品也能下載），存到「檔案」App 可見的 Downloads 資料夾。
    func downloadWork(id: Int, title: String, format: DownloadFormat, href: String?) async throws -> URL {
        let path = href ?? "/downloads/\(id)/work.\(format.rawValue)"
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw AO3Error.invalidSource }
        let (data, response) = try await Self.session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), !data.isEmpty else { throw AO3Error.http(status) }

        let directory = URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(Self.fileName(title)).\(format.rawValue)")
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

/// 閱讀頁工具列的下載按鈕：點擊以預設格式下載，長按選擇其他格式；完成後彈出分享選單。
struct WorkDownloadButton: View {
    let detail: WorkDetail
    let client: AO3Client
    @AppStorage(DownloadFormat.storageKey) private var defaultFormat: DownloadFormat = .epub
    @State private var isDownloading = false
    @State private var file: DownloadedFile?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Section("下載為…") {
                ForEach(DownloadFormat.allCases) { format in
                    Button {
                        download(format)
                    } label: {
                        if format == defaultFormat {
                            Label("\(format.title)（預設）", systemImage: "checkmark")
                        } else {
                            Text(verbatim: format.title)
                        }
                    }
                }
            }
        } label: {
            if isDownloading {
                ProgressView()
            } else {
                Label("下載", systemImage: "arrow.down.circle")
            }
        } primaryAction: {
            download(defaultFormat)
        }
        .disabled(isDownloading)
        .sheet(item: $file) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .alert("下載失敗", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func download(_ format: DownloadFormat) {
        isDownloading = true
        Task {
            defer { isDownloading = false }
            do {
                let url = try await client.downloadWork(id: detail.id, title: detail.title, format: format,
                                                        href: detail.downloads[format.rawValue])
                file = DownloadedFile(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
