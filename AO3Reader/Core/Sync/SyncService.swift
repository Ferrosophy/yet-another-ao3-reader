import Foundation
import Observation

/// 個人資料同步（書架、閱讀時長、閱讀進度、偏好設定）到使用者自選的 iCloud 或 WebDAV。
///
/// 與 AO3 帳號同步完全分開：書籤、稍後閱讀、閱讀紀錄、訂閱、收件匣一律直接讀寫 AO3，
/// 這裡只處理 App 自己的資料，兩邊沒有重疊，不會互相覆蓋。
/// 合併規則：書架與進度以每筆的修改時間為準；閱讀時長每台裝置各自累計後相加；偏好設定取較新的一份。
@MainActor
@Observable
final class SyncService {
    var provider: SyncProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
            lastError = nil
        }
    }
    var webDAV: WebDAVConfig {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(webDAV), forKey: Self.webDAVKey) }
    }
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?

    private let bookshelf: BookshelfStore
    private let readingTime: ReadingTimeStore
    private let appearance: AppearanceSettings
    private let translation: TranslationSettings
    private let searchHistory: SearchHistoryStore
    private var pending: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    private static let providerKey = "sync.provider"
    private static let webDAVKey = "sync.webdav"
    private static let lastSyncKey = "sync.lastSyncAt"
    private static let prefsFingerprintKey = "sync.preferencesFingerprint"
    private static let prefsModifiedKey = "sync.preferencesModifiedAt"
    private static let passwordAccount = "webdav.password"

    init(bookshelf: BookshelfStore, readingTime: ReadingTimeStore, appearance: AppearanceSettings, translation: TranslationSettings,
         searchHistory: SearchHistoryStore) {
        self.searchHistory = searchHistory
        self.bookshelf = bookshelf
        self.readingTime = readingTime
        self.appearance = appearance
        self.translation = translation
        let defaults = UserDefaults.standard
        provider = defaults.string(forKey: Self.providerKey).flatMap(SyncProvider.init) ?? .off
        webDAV = defaults.data(forKey: Self.webDAVKey).flatMap { try? JSONDecoder().decode(WebDAVConfig.self, from: $0) }
            ?? WebDAVConfig()
        let last = defaults.double(forKey: Self.lastSyncKey)
        lastSyncAt = last > 0 ? Date(timeIntervalSince1970: last) : nil
        observer = NotificationCenter.default.addObserver(forName: .personalDataChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
    }

    var webDAVPassword: String {
        get { KeychainStore.read(account: Self.passwordAccount, service: KeychainStore.syncService) ?? "" }
        set { try? KeychainStore.save(newValue, account: Self.passwordAccount, service: KeychainStore.syncService) }
    }

    private func makeBackend() -> (any SyncBackend)? {
        switch provider {
        case .off: nil
        case .iCloud: ICloudBackend()
        case .webDAV: WebDAVBackend(config: webDAV, password: webDAVPassword)
        }
    }

    /// 測試 WebDAV 連線；書架與本機資料同步共用同一組伺服器設定
    func testWebDAV() async throws {
        try await WebDAVBackend(config: webDAV, password: webDAVPassword).test()
    }

    /// 資料變更後延遲同步，合併短時間內的多次變更
    func scheduleSync() {
        guard provider != .off else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            // 先清掉自己，否則 syncNow() 取消 pending 時會連同正在執行的這個任務一起取消
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
            let local = makeSnapshot()
            var remote: SyncSnapshot?
            if let data = try await backend.read() {
                guard let decoded = try? Self.decoder.decode(SyncSnapshot.self, from: data) else { throw SyncError.corrupt }
                remote = decoded
            }
            let merged = merge(local: local, remote: remote)
            apply(merged, local: local)
            try await backend.write(try Self.encoder.encode(merged))
            lastSyncAt = Date()
            UserDefaults.standard.set(lastSyncAt?.timeIntervalSince1970, forKey: Self.lastSyncKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: 快照

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private func currentPreferences() -> SyncedPreferences {
        var appearanceConfig = appearance.config
        // 匯入的字體只存在這台裝置，不同步
        appearanceConfig.customFonts = []
        let defaults = UserDefaults.standard
        var options: [String: String] = [:]
        for key in SyncedPreferences.optionKeys {
            if let value = defaults.string(forKey: key) { options[key] = value }
        }
        var preferences = SyncedPreferences(modifiedAt: .distantPast, appearance: appearanceConfig,
                                            translation: translation.config, options: options)
        // 內容與上次同步時不同，表示在這台裝置上修改過
        let fingerprint = preferences.fingerprint
        // 從未同步過的裝置視為最舊，避免新裝置的預設值覆蓋雲端設定
        if let saved = defaults.string(forKey: Self.prefsFingerprintKey), saved != fingerprint {
            preferences.modifiedAt = Date()
        } else {
            let saved = defaults.double(forKey: Self.prefsModifiedKey)
            preferences.modifiedAt = saved > 0 ? Date(timeIntervalSince1970: saved) : .distantPast
        }
        return preferences
    }

    private func makeSnapshot() -> SyncSnapshot {
        var snapshot = SyncSnapshot()
        snapshot.bookshelf = bookshelf.state
        for item in bookshelf.items {
            if let updatedAt = item.coverUpdatedAt, let data = bookshelf.coverData(item.id) {
                snapshot.covers[String(item.id)] = CoverBlob(updatedAt: updatedAt, data: data)
            }
        }
        snapshot.reading = readingTime.log
        snapshot.progress = ReadingProgress.allLocal()
        snapshot.preferences = currentPreferences()
        snapshot.searchHistory = searchHistory.history
        return snapshot
    }

    private func merge(local: SyncSnapshot, remote: SyncSnapshot?) -> SyncSnapshot {
        guard let remote else { return local }
        var merged = SyncSnapshot()
        merged.bookshelf = SyncMerge.bookshelf(local.bookshelf, remote.bookshelf)
        for item in merged.bookshelf.items {
            guard let updatedAt = item.coverUpdatedAt else { continue }
            let key = String(item.id)
            if let cover = local.covers[key], cover.updatedAt == updatedAt {
                merged.covers[key] = cover
            } else if let cover = remote.covers[key] {
                merged.covers[key] = cover
            }
        }
        merged.reading = local.reading.merged(with: remote.reading)
        merged.progress = SyncMerge.progress(local.progress, remote.progress)
        merged.searchHistory = (local.searchHistory ?? SearchHistory()).merged(with: remote.searchHistory ?? SearchHistory())
        switch (local.preferences, remote.preferences) {
        case let (mine?, theirs?): merged.preferences = theirs.modifiedAt > mine.modifiedAt ? theirs : mine
        case let (mine, theirs): merged.preferences = mine ?? theirs
        }
        return merged
    }

    private func apply(_ merged: SyncSnapshot, local: SyncSnapshot) {
        // 書架：只寫入本機沒有或較舊的封面
        var newCovers: [Int: Data] = [:]
        for (key, cover) in merged.covers where local.covers[key]?.updatedAt != cover.updatedAt {
            if let id = Int(key) { newCovers[id] = cover.data }
        }
        if merged.bookshelf != local.bookshelf || !newCovers.isEmpty {
            bookshelf.apply(merged.bookshelf, covers: newCovers)
        }
        readingTime.apply(merged.reading)
        if let history = merged.searchHistory { searchHistory.apply(history) }
        for (id, progress) in merged.progress where local.progress[id] != progress {
            progress.apply(workID: id)
        }

        let defaults = UserDefaults.standard
        if let preferences = merged.preferences {
            if preferences.modifiedAt > (local.preferences?.modifiedAt ?? .distantPast) {
                applyPreferences(preferences)
            }
            defaults.set(currentPreferencesFingerprint(), forKey: Self.prefsFingerprintKey)
            defaults.set(preferences.modifiedAt.timeIntervalSince1970, forKey: Self.prefsModifiedKey)
        }
    }

    private func applyPreferences(_ preferences: SyncedPreferences) {
        var config = preferences.appearance
        config.customFonts = appearance.config.customFonts
        let localFonts = Set(config.customFonts.map { "custom:\($0.postScriptName)" })
        // 對方使用的匯入字體在這台裝置不存在時保留本機選擇
        if config.readerFont.hasPrefix("custom:"), !localFonts.contains(config.readerFont) {
            config.readerFont = appearance.config.readerFont
        }
        if let font = config.interfaceFont, font.hasPrefix("custom:"), !localFonts.contains(font) {
            config.interfaceFont = appearance.config.interfaceFont
        }
        appearance.config = config
        translation.config = preferences.translation
        for (key, value) in preferences.options where SyncedPreferences.optionKeys.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private func currentPreferencesFingerprint() -> String {
        var preferences = currentPreferences()
        preferences.modifiedAt = .distantPast
        return preferences.fingerprint
    }
}
