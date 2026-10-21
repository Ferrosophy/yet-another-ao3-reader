// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network
import Observation
import SwiftSoup

/// 書架的離線服務：加入書架的作品自動下載原文、翻譯，並以使用者選擇的格式匯出。
///
/// 每部作品保存兩份：
/// - 閱讀用副本（Application Support/Bookshelf/works/<id>/）：原文段落與段落對應的譯文，閱讀頁優先使用。
/// - 匯出檔（Documents/Bookshelf/）：EPUB 由 App 產生雙語版本，其他格式使用 AO3 官網下載，可在「檔案」App 中看到。
///
/// 作品依序處理（每部之間稍作間隔，避免對 AO3 與翻譯服務造成負擔）；有新章節時重新下載，
/// 已翻譯的段落以原文雜湊比對沿用，只翻譯新增或修改的段落。離線狀態只存在這台裝置，不同步；
/// 經同步加入書架的作品會在這台裝置上自動下載。
@MainActor
@Observable
final class OfflineManager {
    private(set) var records: [Int: OfflineRecord] = [:]
    private(set) var activity: [Int: OfflineActivity] = [:]
    /// 每部作品的離線內容大小（位元組）
    private(set) var sizes: [Int: Int64] = [:]
    private(set) var isOnWiFi = true
    private var isOnline = true

    /// 批次下載每次最多選取的作品數
    static let batchLimit = 25
    static let wifiOnlyKey = "offline.wifiOnly"
    static let autoTranslateKey = "offline.autoTranslate"

    private let bookshelf: BookshelfStore
    private let settings: TranslationSettings
    private let translator: TranslationService
    private let makeClient: @MainActor () -> AO3Client

    private var queue: [Int] = []
    /// 需要重新下載原文的作品（有新章節或使用者要求更新）
    private var refresh: Set<Int> = []
    /// 本次啟動中已同意使用付費翻譯 API 的作品
    private var consented: Set<Int> = []
    private var worker: Task<Void, Never>?
    /// 目前處理中的作品；暫停只取消這一部，不影響佇列
    private var job: Task<Void, Never>?
    private var currentID: Int?
    /// 每部作品連續下載失敗的次數（自動重試的間隔依此加長）
    private var failures: [Int: Int] = [:]
    private var observer: NSObjectProtocol?
    private let monitor = NWPathMonitor()

    nonisolated private static let worksDirectory = URL.applicationSupportDirectory
        .appending(path: "Bookshelf/works", directoryHint: .isDirectory)
    nonisolated static let exportDirectory = URL.documentsDirectory.appending(path: "Bookshelf", directoryHint: .isDirectory)
    nonisolated private static let recordsURL = URL.applicationSupportDirectory.appending(path: "Bookshelf/offline.json")

    init(bookshelf: BookshelfStore, settings: TranslationSettings, translator: TranslationService,
         makeClient: @escaping @MainActor () -> AO3Client) {
        self.bookshelf = bookshelf
        self.settings = settings
        self.translator = translator
        self.makeClient = makeClient
        UserDefaults.standard.register(defaults: [Self.autoTranslateKey: true, Self.wifiOnlyKey: false])
        try? FileManager.default.createDirectory(at: Self.worksDirectory, withIntermediateDirectories: true)
        records = (try? Data(contentsOf: Self.recordsURL))
            .flatMap { try? JSONDecoder().decode([Int: OfflineRecord].self, from: $0) } ?? [:]
        for id in records.keys { updateSize(id) }

        observer = NotificationCenter.default.addObserver(forName: .personalDataChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        // 明確標為 @Sendable：這個閉包在背景佇列執行，不能被推斷為主執行緒專用
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            let wifi = online && !path.isExpensive
            Task { @MainActor in self?.networkChanged(wifi: wifi, online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "OfflineManager.network"))
    }

    private var wifiOnly: Bool { UserDefaults.standard.bool(forKey: Self.wifiOnlyKey) }
    private var autoTranslate: Bool { UserDefaults.standard.bool(forKey: Self.autoTranslateKey) }

    // MARK: 查詢

    func hasOfflineCopy(_ id: Int) -> Bool { records[id]?.downloadedAt != nil }

    nonisolated static func workDirectory(_ id: Int) -> URL { worksDirectory.appending(path: String(id), directoryHint: .isDirectory) }
    nonisolated private static func workURL(_ id: Int) -> URL { workDirectory(id).appending(path: "work.json") }
    nonisolated private static func translationsURL(_ id: Int) -> URL { workDirectory(id).appending(path: "translations.json") }

    /// 讀取離線副本（閱讀頁使用）
    nonisolated static func loadWork(_ id: Int) -> OfflineWork? {
        guard let data = try? Data(contentsOf: workURL(id)) else { return nil }
        return try? JSONDecoder().decode(OfflineWork.self, from: data)
    }

    nonisolated static func loadTranslations(_ id: Int) -> OfflineTranslations? {
        guard let data = try? Data(contentsOf: translationsURL(id)) else { return nil }
        return try? JSONDecoder().decode(OfflineTranslations.self, from: data)
    }

    func exportURL(_ id: Int) -> URL? {
        guard let name = records[id]?.exportFileName else { return nil }
        let url = Self.exportDirectory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var totalSize: Int64 { sizes.values.reduce(0, +) }

    /// 分享用的檔案：原文或原文與譯文。
    /// - 原文：匯出格式為官網格式時直接用匯出檔，否則（EPUB）另外產生只有原文的 EPUB。
    /// - 原文與譯文：匯出格式為 EPUB 時直接用匯出檔，否則另外產生雙語 EPUB。
    func shareFile(_ id: Int, bilingual: Bool) -> URL? {
        let format = records[id]?.format ?? .epub
        if (format == .epub) == bilingual, let url = exportURL(id) { return url }
        guard let work = Self.loadWork(id) else { return nil }
        let data = BilingualEPUB.make(work: work, translations: bilingual ? Self.loadTranslations(id) : nil)
        let suffix = bilingual ? String(localized: "原文與譯文") : String(localized: "原文")
        let url = URL.temporaryDirectory.appending(path: "\(AO3Client.fileName(work.title)) (\(suffix)).epub")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: 操作

    /// 加入書架時呼叫：設定匯出格式並開始離線處理
    func add(_ work: WorkSummary, format: DownloadFormat? = nil) {
        var record = records[work.id] ?? OfflineRecord()
        // 只換格式時不重新下載原文，處理時重新匯出即可
        if let format { record.format = format }
        record.contentDeleted = false
        records[work.id] = record
        saveRecords()
        if !bookshelf.contains(work.id) { bookshelf.add(work) }
        enqueue(work.id)
    }

    /// 依書架內容補齊：書架上還沒有離線內容的作品自動下載（含其他裝置同步來的），已移出書架的作品刪除離線內容
    func reconcile() {
        let shelf = Set(bookshelf.items.map(\.id))
        for id in records.keys where !shelf.contains(id) { removeAll(id) }
        for id in shelf where records[id] == nil {
            records[id] = OfflineRecord()
            enqueue(id)
        }
        saveRecords()
    }

    /// App 啟動時繼續上次未完成的作品（下載、翻譯或匯出中斷）
    func resumePending() {
        // 離線頁只顯示離線內容：舊版「刪除離線內容但保留項目」的作品直接移除
        for (id, record) in records where record.contentDeleted { bookshelf.remove(id) }
        reconcile()
        let target = settings.config.targetLanguageCode
        for (id, record) in records where !record.contentDeleted && activity[id] == nil {
            let unfinishedTranslation = autoTranslate && !record.isTranslationComplete
                && !isSameLanguage(record.originalLanguage)
                && (record.translatedLanguage == nil || record.translatedLanguage == target)
            if record.downloadedAt == nil || record.exportFileName == nil || unfinishedTranslation {
                enqueue(id)
            }
        }
    }

    /// 「僅在 Wi-Fi 下載」或「自動翻譯」設定改變後重新排程
    func settingsChanged() {
        for (id, state) in activity where state == .waitingForWiFi { enqueue(id) }
        resumePending()
    }

    func pause(_ id: Int) {
        queue.removeAll { $0 == id }
        if currentID == id { job?.cancel() }
        activity[id] = .paused
    }

    func resume(_ id: Int) {
        enqueue(id)
    }

    /// 同意使用付費翻譯 API 後繼續翻譯
    func consent(_ id: Int) {
        consented.insert(id)
        enqueue(id)
    }

    /// 重新下載原文（檢查新章節或修復損壞的離線內容）
    func update(_ id: Int) {
        refresh.insert(id)
        records[id]?.contentDeleted = false
        enqueue(id)
    }

    /// 以目前的目標語言與翻譯服務重新翻譯（目標語言改變時由使用者手動觸發）
    func retranslate(_ id: Int) {
        try? FileManager.default.removeItem(at: Self.translationsURL(id))
        records[id]?.translatedLanguage = nil
        records[id]?.translatedCount = 0
        saveRecords()
        enqueue(id)
    }

    func setFormat(_ format: DownloadFormat, for id: Int) {
        guard records[id]?.format != format else { return }
        records[id, default: OfflineRecord()].format = format
        saveRecords()
        enqueue(id)
    }

    /// 刪除離線內容但保留書架項目；之後不會自動重新下載，可手動「下載離線內容」
    func deleteContent(_ id: Int) {
        cancel(id)
        removeFiles(id)
        records[id] = OfflineRecord(contentDeleted: true)
        sizes[id] = nil
        saveRecords()
    }

    private func removeAll(_ id: Int) {
        cancel(id)
        removeFiles(id)
        records[id] = nil
        sizes[id] = nil
        activity[id] = nil
    }

    private func cancel(_ id: Int) {
        queue.removeAll { $0 == id }
        refresh.remove(id)
        if currentID == id { job?.cancel() }
        activity[id] = nil
    }

    private func removeFiles(_ id: Int) {
        try? FileManager.default.removeItem(at: Self.workDirectory(id))
        if let url = exportURL(id) { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: 新章節檢查

    /// App 開啟或回到前景時檢查書架作品是否有新章節（每部至少間隔 12 小時，每次最多 10 部）
    func checkUpdates() async {
        let now = Date()
        let due = records.filter { _, record in
            record.downloadedAt != nil && !record.contentDeleted
                && (record.lastCheckedAt ?? .distantPast) < now.addingTimeInterval(-12 * 3600)
        }.keys.prefix(10)
        guard !due.isEmpty, !(wifiOnly && !isOnWiFi) else { return }
        let client = makeClient()
        for id in due {
            guard let count = try? await client.publishedChapterCount(id: id) else { continue }
            records[id]?.lastCheckedAt = Date()
            if count > (records[id]?.chapterCount ?? 0) {
                refresh.insert(id)
                enqueue(id)
            }
            try? await Task.sleep(for: .seconds(1))
        }
        saveRecords()
    }

    // MARK: 佇列

    private func enqueue(_ id: Int) {
        // 處理中的作品再次排入時（例如更新或重新翻譯），完成目前這輪後再處理一次
        if !queue.contains(id) { queue.append(id) }
        if currentID != id { activity[id] = .queued }
        run()
    }

    private func networkChanged(wifi: Bool, online: Bool) {
        let wasOnline = isOnline
        isOnWiFi = wifi
        isOnline = online
        if wifi {
            for (id, state) in activity where state == .waitingForWiFi { enqueue(id) }
        }
        // 網路恢復：下載中斷的作品立即從斷點繼續
        if online, !wasOnline {
            for (id, state) in activity where needsDownload(id) {
                if case .failed = state { enqueue(id) }
            }
        }
    }

    /// AO3 限流（HTTP 429）後，整個佇列暫停到這個時間，不再接著請求其他作品
    @ObservationIgnored private var rateLimitedUntil: Date?

    private func run() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let id = self.nextID() {
                if let until = self.rateLimitedUntil, until > Date() {
                    try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
                }
                self.currentID = id
                let job = Task { await self.process(id) }
                self.job = job
                await job.value
                self.job = nil
                self.currentID = nil
                try? await Task.sleep(for: .seconds(1))
            }
            self?.worker = nil
        }
    }

    /// 先處理還沒有原文的作品（全部原文都離線後才開始翻譯），翻譯較慢且較容易失敗，不會擋住其他作品的下載
    private func nextID() -> Int? {
        guard !queue.isEmpty else { return nil }
        if let index = queue.firstIndex(where: needsDownload) { return queue.remove(at: index) }
        return queue.removeFirst()
    }

    private func needsDownload(_ id: Int) -> Bool {
        records[id]?.downloadedAt == nil || refresh.contains(id)
    }

    /// 下載整部作品。先嘗試一次取得完整內容頁；逾時或網路中斷時改為逐章下載，
    /// 每章下載完就存到作品資料夾，失敗或中斷後從下一章繼續（斷點續傳）。
    private func downloadWork(_ id: Int) async throws -> WorkDetail {
        if let partial = Self.loadPartial(id) {
            return try await downloadByChapters(id, resume: partial)
        }
        do {
            return try await withRetry { try await makeClient().work(id: id) }
        } catch let error where Self.isConnectionError(error) {
            return try await downloadByChapters(id, resume: nil)
        }
    }

    private func downloadByChapters(_ id: Int, resume: OfflinePartial?) async throws -> WorkDetail {
        let client = makeClient()
        var partial: OfflinePartial
        if let resume {
            partial = resume
        } else {
            partial = OfflinePartial(chapterIDs: try await withRetry { try await client.chapterIDs(workID: id) })
        }
        guard !partial.chapterIDs.isEmpty else { throw AO3Error.parse(String(localized: "作品沒有章節")) }
        let total = partial.chapterIDs.count
        for index in partial.downloadedCount..<total {
            try Task.checkCancellation()
            activity[id] = .downloadingChapters(done: index, total: total)
            let chapterID = partial.chapterIDs[index]
            let page = try await withRetry { try await client.chapter(workID: id, chapterID: chapterID, index: index) }
            if var work = partial.work {
                work.chapters += page.chapters
                // 作品結尾註在最後一章的頁面
                if index == total - 1, !page.endNotes.isEmpty { work.endNotes = page.endNotes }
                partial.work = work
            } else {
                partial.work = OfflineWork(detail: page)
            }
            try write(partial, to: Self.partialURL(id))
            if index < total - 1 { try await Task.sleep(for: .seconds(1)) }
        }
        try? FileManager.default.removeItem(at: Self.partialURL(id))
        guard let work = partial.work else { throw AO3Error.parse(String(localized: "作品沒有章節")) }
        return work.detail
    }

    /// AO3 限流、伺服器錯誤或網路錯誤時稍候重試（最多 3 次）
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch let error as AO3Error {
                attempt += 1
                switch error {
                case .rateLimited(let after) where attempt < 3:
                    try await Task.sleep(for: .seconds(min(Double(after ?? "") ?? 30, 120)))
                case .http(let code) where code >= 500 && attempt < 3:
                    try await Task.sleep(for: .seconds(5 * attempt))
                default:
                    throw error
                }
            } catch let error as URLError where attempt < 2 && error.code != .cancelled {
                attempt += 1
                try await Task.sleep(for: .seconds(5 * attempt))
            }
        }
    }

    /// 逾時、斷線或伺服器暫時錯誤（改用逐章下載、或稍後自動重試的情況）
    private static func isConnectionError(_ error: Error) -> Bool {
        if let error = error as? URLError { return error.code != .cancelled }
        if case AO3Error.http(let code) = error { return code >= 500 }
        return false
    }

    /// 作品的原文語言（AO3 的語言名稱）是否就是目前的目標語言（中文不分繁簡）
    func isSameLanguage(_ languageName: String?) -> Bool {
        guard let name = languageName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return false }
        let code = (languageCodes[name] ?? Self.commonLanguageCodes[name])?.lowercased()
        guard let code else { return false }
        let target = settings.config.targetLanguageCode.lowercased()
        let base = String(target.prefix { $0 != "-" })
        // AO3 的葡萄牙語代碼為 ptBR / ptPT
        return code == base || code == target.replacingOccurrences(of: "-", with: "")
            || (base.count == 2 && code.count == 4 && code.hasPrefix(base))
    }

    /// AO3 語言名稱 → 代碼（只建立一次：每次都解碼語言清單會讓狀態列表重繪變得很慢）
    @ObservationIgnored private var languageCodeCache: [String: String]?
    private var languageCodes: [String: String] {
        if let cache = languageCodeCache { return cache }
        let map = Dictionary(LatestWorksView.cachedLanguages().map { ($0.name, $0.code) }, uniquingKeysWith: { first, _ in first })
        languageCodeCache = map
        return map
    }

    /// 語言清單尚未從 AO3 讀取時使用的常見語言
    private static let commonLanguageCodes: [String: String] = [
        "English": "en", "中文-普通话 國語": "zh", "日本語": "ja", "한국어": "ko", "Español": "es", "Français": "fr",
        "Deutsch": "de", "Русский": "ru", "Italiano": "it", "Português brasileiro": "ptBR", "Português europeu": "ptPT",
        "Polski": "pl", "Türkçe": "tr", "Tiếng Việt": "vi", "ไทย": "th", "Bahasa Indonesia": "id", "العربية": "ar",
        "Українська": "uk", "Nederlands": "nl",
    ]

    /// 可以稍後自動重試的錯誤：連線問題或 AO3 限流
    private static func isRetryable(_ error: Error) -> Bool {
        if case AO3Error.rateLimited = error { return true }
        return isConnectionError(error)
    }

    nonisolated private static func partialURL(_ id: Int) -> URL { workDirectory(id).appending(path: "partial.json") }

    nonisolated private static func loadPartial(_ id: Int) -> OfflinePartial? {
        guard let data = try? Data(contentsOf: partialURL(id)) else { return nil }
        return try? JSONDecoder().decode(OfflinePartial.self, from: data)
    }

    /// 下載失敗後自動重試：等待時間逐次加長（30 秒、1、2、4、8 分鐘），網路恢復時立即重試
    private func scheduleAutoRetry(_ id: Int) {
        let count = (failures[id] ?? 0) + 1
        failures[id] = count
        guard count <= 5 else { return }
        let delay = 30.0 * pow(2, Double(count - 1))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, case .failed = self.activity[id] else { return }
            self.enqueue(id)
        }
    }

    private func process(_ id: Int) async {
        guard bookshelf.contains(id) else { return }
        if wifiOnly && !isOnWiFi {
            activity[id] = .waitingForWiFi
            return
        }
        do {
            // 1. 原文：下載後先匯出原文版本，再排到佇列後面等待翻譯
            if Self.loadWork(id) == nil || refresh.contains(id) {
                activity[id] = .downloading
                let detail = try await downloadWork(id)
                try Task.checkCancellation()
                let downloaded = OfflineWork(detail: detail)
                try write(downloaded, to: Self.workURL(id))
                refresh.remove(id)
                failures[id] = nil
                records[id, default: OfflineRecord()].chapterCount = detail.chapters.count
                records[id]?.downloadedAt = downloaded.downloadedAt
                records[id]?.lastCheckedAt = Date()
                records[id]?.hasUpdate = false
                saveRecords()
                activity[id] = .exporting
                try await export(downloaded)
                updateSize(id)
                records[id]?.originalLanguage = downloaded.info?.language
                // 原文已經是目標語言時只下載原文，不翻譯
                if autoTranslate, !isSameLanguage(downloaded.info?.language) {
                    // 翻譯在所有原文都下載完之後進行
                    activity[id] = .queued
                    if !queue.contains(id) { queue.append(id) }
                } else {
                    activity[id] = nil
                }
                saveRecords()
                return
            }
            guard let work = Self.loadWork(id) else { return }

            // 2. 翻譯（失敗時仍匯出原文，狀態顯示翻譯錯誤，可重試）
            var outcome: OfflineActivity?
            do {
                outcome = try await translate(work)
            } catch let error where !(error is CancellationError) && !Task.isCancelled {
                outcome = .failed(String(localized: "翻譯失敗：\(error.localizedDescription)"))
            }
            try Task.checkCancellation()

            // 3. 匯出
            activity[id] = .exporting
            try await export(work)
            try Task.checkCancellation()
            updateSize(id)
            activity[id] = outcome
        } catch is CancellationError {
            if activity[id] != nil { activity[id] = .paused }
        } catch {
            if Task.isCancelled {
                if activity[id] != nil { activity[id] = .paused }
            } else if needsDownload(id), Self.isRetryable(error) {
                if case AO3Error.rateLimited(let after) = error {
                    rateLimitedUntil = Date().addingTimeInterval(max(Double(after ?? "") ?? 60, 60))
                }
                // 下載失敗：已下載的章節保留，稍後自動從斷點繼續
                activity[id] = .failed(String(localized: "下載中斷：\(error.localizedDescription)，稍後自動繼續"))
                scheduleAutoRetry(id)
            } else {
                activity[id] = .failed(String(localized: "失敗：\(error.localizedDescription)"))
            }
        }
        saveRecords()
    }

    /// 翻譯缺少的段落；回傳結束後要顯示的狀態（nil 為完成，或等待同意使用付費 API）
    private func translate(_ work: OfflineWork) async throws -> OfflineActivity? {
        let id = work.id
        let paragraphs = work.translatableParagraphs
        let target = settings.config.targetLanguageCode
        var translations = Self.loadTranslations(id) ?? OfflineTranslations(targetLanguageCode: target)
        records[id]?.translatableCount = paragraphs.count
        records[id]?.originalLanguage = work.info?.language

        // 原文與目標語言相同：不需要翻譯
        if isSameLanguage(work.info?.language) {
            records[id]?.translatedCount = 0
            return nil
        }

        // 已有其他語言的譯文時不自動覆蓋，由使用者手動「重新翻譯」
        guard autoTranslate, translations.targetLanguageCode == target else {
            records[id]?.translatedCount = paragraphs.filter { translations.text(for: $0) != nil }.count
            return nil
        }
        let missing = paragraphs.filter { translations.text(for: $0) == nil }
        records[id]?.translatedCount = paragraphs.count - missing.count
        guard !missing.isEmpty else {
            records[id]?.translatedLanguage = target
            return nil
        }

        // 付費 API 先詢問使用者
        let kind = settings.config.provider
        let isPaid = kind.requiresAPIKey || (kind == .deepL && settings.hasAPIKey(for: .deepL))
        if isPaid, !consented.contains(id) { return .awaitingConsent }

        let provider = try settings.makeProvider()
        let source = settings.config.sourceLanguage
        let language = settings.config.targetLanguage
        var done = paragraphs.count - missing.count
        var index = 0
        activity[id] = .translating(done: done, total: paragraphs.count)
        while index < missing.count {
            try Task.checkCancellation()
            if wifiOnly && !isOnWiFi { return .waitingForWiFi }
            var batch: [Paragraph] = []
            var characters = 0
            while index < missing.count {
                let paragraph = missing[index]
                if !batch.isEmpty, characters + paragraph.text.count > provider.maxBatchCharacters { break }
                batch.append(paragraph)
                characters += paragraph.text.count
                index += 1
            }
            let results = try await translator.translate(paragraphs: batch, provider: provider, source: source, target: language)
            for (paragraph, text) in zip(batch, results) {
                translations.entries[paragraph.id] = .init(hash: OfflineTranslations.hash(paragraph.text), text: text)
            }
            done += batch.count
            // 每批都寫入，暫停或中斷後可從這裡繼續
            try write(translations, to: Self.translationsURL(id))
            records[id]?.translatedCount = done
            records[id]?.translatedLanguage = target
            activity[id] = .translating(done: done, total: paragraphs.count)
            try? await Task.sleep(for: .milliseconds(300))
        }
        return nil
    }

    private func export(_ work: OfflineWork) async throws {
        let id = work.id
        let format = records[id]?.format ?? DownloadFormat(rawValue: UserDefaults.standard.string(forKey: DownloadFormat.storageKey) ?? "") ?? .epub
        try FileManager.default.createDirectory(at: Self.exportDirectory, withIntermediateDirectories: true)
        let name = "\(AO3Client.fileName(work.title)) (\(id)).\(format.rawValue)"
        let url = Self.exportDirectory.appending(path: name)
        if let old = records[id]?.exportFileName, old != name {
            try? FileManager.default.removeItem(at: Self.exportDirectory.appending(path: old))
        }
        switch format {
        case .epub:
            let data = BilingualEPUB.make(work: work, translations: Self.loadTranslations(id))
            try data.write(to: url, options: .atomic)
        default:
            // 官網格式不含譯文，章節沒有變化時不重新下載
            let current = FileManager.default.fileExists(atPath: url.path)
                && records[id]?.exportFileName == name
                && (records[id]?.exportedChapterCount ?? 0) == work.chapters.count
            if !current {
                _ = try await makeClient().downloadWork(id: id, title: work.title, format: format, href: nil,
                                                        directory: Self.exportDirectory, fileName: name)
            }
        }
        records[id]?.format = format
        records[id]?.exportFileName = name
        records[id]?.exportedChapterCount = work.chapters.count
        saveRecords()
    }

    // MARK: 儲存

    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func saveRecords() {
        try? JSONEncoder().encode(records).write(to: Self.recordsURL, options: .atomic)
    }

    private func updateSize(_ id: Int) {
        let directory = Self.workDirectory(id)
        let export = exportURL(id)
        Task { [weak self] in
            let size = await Task.detached(priority: .utility) {
                Self.directorySize(directory) + (export.map { Self.fileSize($0) } ?? 0)
            }.value
            self?.sizes[id] = size > 0 ? size : nil
        }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files { total += fileSize(file) }
        return total
    }
}

extension AO3Client {
    /// 作品各章的 ID（目錄頁 /works/<id>/navigate），供逐章下載
    func chapterIDs(workID: Int) async throws -> [Int] {
        if isDemo {
            let count = try DemoSite.detail(id: workID).chapters.count
            return Array(0..<count)
        }
        let html = try await get("/works/\(workID)/navigate", query: [URLQueryItem(name: "view_adult", value: "true")])
        return try AO3Parser.chapterIDs(html: html)
    }

    /// 單章頁面；`index` 為這一章在整部作品中的索引（段落 ID 與完整內容頁一致）
    func chapter(workID: Int, chapterID: Int, index: Int) async throws -> WorkDetail {
        if isDemo {
            var detail = try DemoSite.detail(id: workID)
            detail.chapters = detail.chapters.indices.contains(index) ? [detail.chapters[index]] : []
            return detail
        }
        let html = try await get("/works/\(workID)/chapters/\(chapterID)", query: [URLQueryItem(name: "view_adult", value: "true")])
        return try AO3Parser.workDetail(html: html, id: workID, chapterOffset: index)
    }

    /// 作品目前已發布的章節數（作品頁統計列「3/10」的前半）
    func publishedChapterCount(id: Int) async throws -> Int? {
        if isDemo { return try DemoSite.detail(id: id).chapters.count }
        let html = try await get("/works/\(id)", query: [URLQueryItem(name: "view_adult", value: "true")])
        let text = try SwiftSoup.parse(html).select("dl.stats dd.chapters").first()?.text() ?? ""
        return Int(text.split(separator: "/").first?.trimmingCharacters(in: .whitespaces).filter(\.isNumber) ?? "")
    }
}
