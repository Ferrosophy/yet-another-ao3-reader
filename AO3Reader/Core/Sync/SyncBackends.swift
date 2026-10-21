// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum SyncError: LocalizedError {
    case iCloudUnavailable
    case unauthorized
    case invalidServer
    case http(Int)
    case corrupt

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            String(localized: "無法使用 iCloud：請確認已登入 iCloud 並開啟 iCloud 雲碟，且簽名時保留了 iCloud 能力")
        case .unauthorized: String(localized: "WebDAV 帳號或應用密碼錯誤")
        case .invalidServer: String(localized: "WebDAV 伺服器位址無效")
        case .http(let code): String(localized: "同步伺服器回應錯誤（HTTP \(code)）")
        case .corrupt: String(localized: "雲端的同步檔案無法讀取")
        }
    }
}

protocol SyncBackend: Sendable {
    /// 讀取雲端的同步檔案；尚未建立時回傳 nil
    func read() async throws -> Data?
    func write(_ data: Data) async throws
    func test() async throws
}

/// WebDAV（例如堅果雲）：在指定資料夾中存放一個 JSON 檔。
struct WebDAVBackend: SyncBackend {
    let config: WebDAVConfig
    let password: String
    /// 書架與本機使用者資料各用一個檔案
    var fileName = SyncSnapshot.fileName

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    private var serverURL: URL {
        get throws {
            var text = config.server.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.hasSuffix("/") { text += "/" }
            guard let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { throw SyncError.invalidServer }
            return url
        }
    }

    /// 資料夾路徑的每一層。留空時使用 AO3Reader：堅果雲等服務不允許把檔案直接放在 WebDAV 根目錄（PUT 會回 409）
    private var folderComponents: [String] {
        let components = config.folder.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return components.isEmpty ? ["AO3Reader"] : components
    }

    private var folderURL: URL {
        get throws {
            var url = try serverURL
            for component in folderComponents { url = url.appending(path: component + "/", directoryHint: .isDirectory) }
            return url
        }
    }

    /// 逐層建立資料夾（已存在時伺服器回 405，視為成功）
    private func createFolders() async throws {
        var url = try serverURL
        for component in folderComponents {
            url = url.appending(path: component + "/", directoryHint: .isDirectory)
            let (_, response) = try await Self.session.data(for: request(url, method: "MKCOL"))
            switch status(response) {
            case 200..<300, 405: continue
            case 401, 403: throw SyncError.unauthorized
            case let code: throw SyncError.http(code)
            }
        }
    }

    private var fileURL: URL {
        get throws { try folderURL.appending(path: fileName) }
    }

    private func request(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let credentials = Data("\(config.username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func status(_ response: URLResponse) -> Int { (response as? HTTPURLResponse)?.statusCode ?? 0 }

    func read() async throws -> Data? {
        let (data, response) = try await Self.session.data(for: request(try fileURL, method: "GET"))
        switch status(response) {
        case 200..<300: return data
        case 404: return nil
        case 401, 403: throw SyncError.unauthorized
        case let code: throw SyncError.http(code)
        }
    }

    func write(_ data: Data) async throws {
        var put = request(try fileURL, method: "PUT")
        put.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var (_, response) = try await Self.session.upload(for: put, from: data)
        if status(response) == 409 {
            // 409：上層資料夾不存在，建立後重試一次
            try await createFolders()
            (_, response) = try await Self.session.upload(for: put, from: data)
        }
        switch status(response) {
        case 200..<300: return
        case 401, 403: throw SyncError.unauthorized
        case let code: throw SyncError.http(code)
        }
    }

    /// 測試連線：確認帳號密碼，並建立同步用的資料夾（同步時才不會因資料夾不存在而失敗）
    func test() async throws {
        try await createFolders()
        var propfind = request(try folderURL, method: "PROPFIND")
        propfind.setValue("0", forHTTPHeaderField: "Depth")
        let (_, response) = try await Self.session.data(for: propfind)
        switch status(response) {
        case 200..<300: return
        case 401, 403: throw SyncError.unauthorized
        case let code: throw SyncError.http(code)
        }
    }
}

/// iCloud 雲碟：存放在 App 的 iCloud 容器中（需要簽名時包含 iCloud Documents 能力）。
struct ICloudBackend: SyncBackend {
    var fileName = SyncSnapshot.fileName

    private func fileURL() async throws -> URL {
        guard FileManager.default.ubiquityIdentityToken != nil else { throw SyncError.iCloudUnavailable }
        // 第一次取得容器位址可能需要一些時間，不在主執行緒進行
        let container = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: nil) }.value
        guard let container else { throw SyncError.iCloudUnavailable }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents.appending(path: fileName)
    }

    func read() async throws -> Data? {
        let url = try await fileURL()
        // 檔案可能只在雲端：要求下載並等待最多約 10 秒
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<20 {
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values?.ubiquitousItemDownloadingStatus == .current { break }
            if values == nil, !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        if let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus,
           status != .current {
            // 雲端檔案尚未下載完成：不可視為「沒有檔案」，否則會用本機資料覆蓋雲端
            throw SyncError.iCloudUnavailable
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try await Task.detached {
            var result: Result<Data, Error> = .failure(SyncError.corrupt)
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                result = Result { try Data(contentsOf: readURL) }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }.value
    }

    func write(_ data: Data) async throws {
        let url = try await fileURL()
        try await Task.detached {
            var result: Result<Void, Error> = .success(())
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
                result = Result { try data.write(to: writeURL, options: .atomic) }
            }
            if let coordinationError { throw coordinationError }
            try result.get()
        }.value
    }

    func test() async throws {
        _ = try await fileURL()
    }
}
