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
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.status == .satisfied && !path.isExpensive
            Task { @MainActor in self?.networkChanged(wifi: wifi) }
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

    /// 閱讀頁手動重譯某段後，同步更新離線譯文（語言相同才寫入）
    nonisolated static func saveTranslation(_ text: String, for paragraph: Paragraph, workID: Int, targetLanguageCode: String) {
        guard var translations = loadTranslations(workID), translations.targetLanguageCode == targetLanguageCode else { return }
        translations.entries[paragraph.id] = .init(hash: OfflineTranslations.hash(paragraph.text), text: text)
        try? JSONEncoder().encode(translations).write(to: translationsURL(workID), options: .atomic)
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

    private func networkChanged(wifi: Bool) {
        isOnWiFi = wifi
        if wifi {
            for (id, state) in activity where state == .waitingForWiFi { enqueue(id) }
        }
    }

    private func run() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let id = self.nextID() {
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

    /// 下載整部作品；網路錯誤或 AO3 限流時稍候重試（最多 3 次）
    private func downloadWork(_ id: Int) async throws -> WorkDetail {
        var attempt = 0
        while true {
            do {
                return try await makeClient().work(id: id)
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
                records[id, default: OfflineRecord()].chapterCount = detail.chapters.count
                records[id]?.downloadedAt = downloaded.downloadedAt
                records[id]?.lastCheckedAt = Date()
                records[id]?.hasUpdate = false
                saveRecords()
                activity[id] = .exporting
                try await export(downloaded)
                updateSize(id)
                if autoTranslate {
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
    /// 作品目前已發布的章節數（作品頁統計列「3/10」的前半）
    func publishedChapterCount(id: Int) async throws -> Int? {
        let html = try await get("/works/\(id)", query: [URLQueryItem(name: "view_adult", value: "true")])
        let text = try SwiftSoup.parse(html).select("dl.stats dd.chapters").first()?.text() ?? ""
        return Int(text.split(separator: "/").first?.trimmingCharacters(in: .whitespaces).filter(\.isNumber) ?? "")
    }
}
