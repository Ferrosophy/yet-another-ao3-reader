// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// 本機使用者資料（書籤、稍後閱讀、閱讀紀錄、訂閱）的同步。
/// 只在資料來源為「本機保存」時運作；服務商（iCloud / WebDAV）與書架同步分開選擇，
/// WebDAV 伺服器設定兩者共用，各自存成不同的檔案。
@MainActor
@Observable
final class LibrarySyncService {
    var provider: SyncProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
            lastError = nil
        }
    }
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?

    private let library: LocalLibraryStore
    private let shelfSync: SyncService
    private var pending: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    private static let providerKey = "sync.library.provider"
    private static let lastSyncKey = "sync.library.lastSyncAt"

    init(library: LocalLibraryStore, shelfSync: SyncService) {
        self.library = library
        self.shelfSync = shelfSync
        let defaults = UserDefaults.standard
        provider = defaults.string(forKey: Self.providerKey).flatMap(SyncProvider.init) ?? .off
        let last = defaults.double(forKey: Self.lastSyncKey)
        lastSyncAt = last > 0 ? Date(timeIntervalSince1970: last) : nil
        observer = NotificationCenter.default.addObserver(forName: .localLibraryChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
    }

    private func makeBackend() -> (any SyncBackend)? {
        guard DataSource.current == .local else { return nil }
        switch provider {
        case .off: return nil
        case .iCloud: return ICloudBackend(fileName: LocalLibrary.fileName)
        case .webDAV: return WebDAVBackend(config: shelfSync.webDAV, password: shelfSync.webDAVPassword, fileName: LocalLibrary.fileName)
        }
    }

    func scheduleSync() {
        guard provider != .off else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            await self.syncNow()
        }
    }

    func syncNow() async {
        guard let backend = makeBackend(), !isSyncing else { return }
        pending?.cancel()
        isSyncing = true
        defer { isSyncing = false }
        do {
            var merged = library.library
            if let data = try await backend.read() {
                guard let remote = try? JSONDecoder().decode(LocalLibrary.self, from: data) else { throw SyncError.corrupt }
                merged = merged.merged(with: remote)
            }
            library.apply(merged)
            try await backend.write(try JSONEncoder().encode(merged))
            lastSyncAt = Date()
            UserDefaults.standard.set(lastSyncAt?.timeIntervalSince1970, forKey: Self.lastSyncKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
