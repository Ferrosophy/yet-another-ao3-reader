// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

enum ParagraphTranslation: Hashable, Sendable {
    case loading
    case done(String)
    case failed(String)
}

/// 閱讀器狀態與沉浸式翻譯排程。
///
/// 翻譯策略：段落出現在螢幕上時（並預取後面幾段）加入佇列，短暫防抖後依服務的
/// `maxBatchCharacters` 合併成批次送出。譯文以段落 ID 對應，顯示在原文正下方，不取代原文。
/// 切換語言或服務時遞增 `generation`，丟棄舊批次的結果。
@MainActor
@Observable
final class ReaderViewModel {
    let route: WorkRoute

    private(set) var detail: WorkDetail?
    private(set) var loadError: String?
    private(set) var requiresLogin = false
    private(set) var chapterIndex = 0
    /// 所有段落的譯文。不直接被畫面觀察（避免一段譯文送達就重繪整章）：
    /// 捲動模式每段只觀察自己的 `slot`；翻頁模式使用節流更新的 `renderedTranslations`。
    @ObservationIgnored private(set) var translations: [Paragraph.ID: ParagraphTranslation] = [:] {
        didSet {
            for (id, slot) in slots where slot.value != translations[id] { slot.value = translations[id] }
            scheduleRender()
        }
    }
    /// 翻頁模式排版用的譯文快照，最多每 0.5 秒更新一次（每次更新都要重新分頁整章）
    private(set) var renderedTranslations: [Paragraph.ID: ParagraphTranslation] = [:]
    /// renderedTranslations 的版本號，用於翻頁內容的快取簽章（不必每次雜湊整個字典）
    private(set) var renderVersion = 0
    @ObservationIgnored private var slots: [Paragraph.ID: TranslationSlot] = [:]
    @ObservationIgnored private var renderTask: Task<Void, Never>?

    /// 單一段落的譯文狀態（畫面只觀察需要的段落）
    func slot(_ id: Paragraph.ID) -> TranslationSlot {
        if let slot = slots[id] { return slot }
        let slot = TranslationSlot()
        slot.value = translations[id]
        slots[id] = slot
        return slot
    }

    private func scheduleRender() {
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.renderTask = nil
            self.renderedTranslations = self.translations
            self.renderVersion += 1
        }
    }
    private(set) var translationError: String?
    /// 翻譯服務要求驗證（網頁驗證碼或 Apple 語言下載）時由閱讀頁彈出視窗
    var challenge: TranslationChallenge?
    /// 同一個驗證只自動彈出一次，避免使用者直接關閉後反覆彈出
    private var presentedChallenges: Set<String> = []

    /// 目前畫面頂端的段落 ID（ScrollView 的 scrollPosition），用於保持捲動位置與記住閱讀進度。
    var scrollAnchor: String? {
        didSet {
            guard let scrollAnchor, scrollAnchor != oldValue else { return }
            UserDefaults.standard.set(scrollAnchor, forKey: anchorKey)
            ReadingProgress.touch(route.id)
        }
    }

    var isTranslationOn = false {
        didSet {
            guard isTranslationOn != oldValue else { return }
            if isTranslationOn { enqueueVisible() } else { cancelPending() }
        }
    }

    let client: AO3Client
    private let settings: TranslationSettings
    private let translator: TranslationService

    private var lookup: [Paragraph.ID: Paragraph] = [:]
    private var visible: Set<Paragraph.ID> = []
    private var queue: [Paragraph.ID] = []
    private var flushTask: Task<Void, Never>?
    private var generation = 0

    /// 每段出現時，一併預取其後的段落數
    private let prefetchCount = 4

    init(route: WorkRoute, app: AppState) {
        self.route = route
        self.client = app.client
        self.settings = app.translation
        self.translator = app.translator
    }

    var chapter: Chapter? {
        guard let chapters = detail?.chapters, chapters.indices.contains(chapterIndex) else { return nil }
        return chapters[chapterIndex]
    }

    /// 整部作品的閱讀進度（0...1）：以畫面上最後一個正文段落在全部正文段落中的位置計算
    var progress: Double {
        guard let chapters = detail?.chapters else { return 0 }
        let total = chapters.reduce(0) { $0 + $1.paragraphs.count }
        guard total > 0 else { return 0 }
        let before = chapters.prefix(chapterIndex).reduce(0) { $0 + $1.paragraphs.count }
        // 段落 ID 為「c<章>-p<段>」
        let prefix = "c\(chapterIndex)-p"
        let last = visible.compactMap { $0.hasPrefix(prefix) ? Int($0.dropFirst(prefix.count)) : nil }.max()
        return min(1, Double(before + (last.map { $0 + 1 } ?? 0)) / Double(total))
    }

    var hasPrevious: Bool { chapterIndex > 0 }
    var hasNext: Bool { chapterIndex + 1 < (detail?.chapters.count ?? 0) }
    var targetLanguage: TranslationLanguage { settings.config.targetLanguage }
    var displayMode: BilingualDisplayMode { settings.config.displayMode }

    // MARK: - Loading

    /// 是否正在閱讀書架的離線副本
    private(set) var isOffline = false

    func load() async {
        guard detail == nil else { return }
        // 書架上已離線的作品直接讀取本機副本，不需要網路
        if let offline = OfflineManager.loadWork(route.id) {
            isOffline = true
            show(offline.detail)
            applyOfflineTranslations()
            await loadActions()
            return
        }
        do {
            show(try await client.work(id: route.id))
            applyOfflineTranslations()
        } catch AO3Error.requiresLogin {
            requiresLogin = true
            loadError = AO3Error.requiresLogin.localizedDescription
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func show(_ detail: WorkDetail) {
        for chapter in detail.chapters {
            for paragraph in chapter.paragraphs { lookup[paragraph.id] = paragraph }
        }
        for paragraph in Self.metaParagraphs(detail: detail, chapters: detail.chapters.indices, includeAll: true) {
            lookup[paragraph.id] = paragraph
        }
        let saved = UserDefaults.standard.integer(forKey: positionKey)
        chapterIndex = min(max(saved, 0), detail.chapters.count - 1)
        self.detail = detail
        // 只在同一章時恢復段落位置
        if let anchor = UserDefaults.standard.string(forKey: anchorKey), anchor.hasPrefix("c\(chapterIndex)-") {
            scrollAnchor = anchor
        }
    }

    /// 離線譯文的目標語言與目前設定相同時直接填入，不必重新翻譯
    private func applyOfflineTranslations() {
        guard let saved = OfflineManager.loadTranslations(route.id),
              saved.targetLanguageCode == settings.config.targetLanguageCode else { return }
        for paragraph in lookup.values where translations[paragraph.id] == nil {
            if let text = saved.text(for: paragraph) { translations[paragraph.id] = .done(text) }
        }
    }

    /// 離線閱讀時，連線可用則在背景讀取帳號操作（書籤、訂閱等），失敗不影響閱讀
    private func loadActions() async {
        guard let actions = try? await client.workActions(id: route.id) else { return }
        detail?.actions = actions
    }

    private var positionKey: String { "reader.position.\(route.id)" }
    private var anchorKey: String { "reader.anchor.\(route.id)" }

    /// 每章頂部標題區塊的捲動 ID
    static func headerID(_ chapter: Int) -> String { "header-\(chapter)" }

    // MARK: - Chapters

    /// 第一章章節標題（作品資訊之後）的捲動 ID；翻頁模式以它表示「第一個正文頁」
    static func chapterTextID(_ chapter: Int) -> String { "chaptertext-\(chapter)" }

    /// `skipWorkInfo`：從目錄選章時跳過第一章前面的作品資訊，直接到章節開頭
    func goToChapter(_ index: Int, skipWorkInfo: Bool = false) {
        guard let detail, detail.chapters.indices.contains(index) else { return }
        chapterIndex = index
        visible.removeAll()
        scrollAnchor = skipWorkInfo && index == 0 ? Self.chapterTextID(index) : Self.headerID(index)
        UserDefaults.standard.set(index, forKey: positionKey)
        ReadingProgress.touch(route.id)
    }

    func nextChapter() { goToChapter(chapterIndex + 1) }
    func previousChapter() { goToChapter(chapterIndex - 1) }

    // MARK: - Immersive translation

    /// 簡介與章節標題也以段落形式排入同一個翻譯佇列（ID 以 meta- 開頭，不會與正文衝突）
    nonisolated static let summaryID = "meta-summary"
    nonisolated static let workTitleID = "meta-worktitle"
    nonisolated static let notesID = "meta-notes"
    nonisolated static let endNotesID = "meta-endnotes"
    nonisolated static func chapterTitleID(_ chapter: Int) -> String { "meta-title-c\(chapter)" }
    nonisolated static func chapterNotesID(_ chapter: Int) -> String { "meta-notes-c\(chapter)" }
    nonisolated static func chapterEndNotesID(_ chapter: Int) -> String { "meta-endnotes-c\(chapter)" }

    /// `includeAll` 為 true 時忽略「顯示譯文」設定（離線翻譯一次備齊）
    nonisolated static func metaParagraphs(detail: WorkDetail, chapters: some Sequence<Int>, includeAll: Bool = false) -> [Paragraph] {
        var result: [Paragraph] = []
        func add(_ id: String, _ text: String, kind: Paragraph.Kind = .body) {
            if !text.isEmpty { result.append(Paragraph(id: id, text: text, kind: kind)) }
        }
        for index in chapters where detail.chapters.indices.contains(index) {
            let chapter = detail.chapters[index]
            if index == 0 {
                // 設定 › 一般 › 顯示譯文
                if includeAll || TranslationVisibility.readerTitle { add(workTitleID, detail.title, kind: .heading) }
                if includeAll || TranslationVisibility.readerSummary { add(summaryID, detail.summary) }
                if includeAll || TranslationVisibility.readerNotes { add(notesID, detail.notes) }
            }
            if detail.chapters.count > 1 { add(chapterTitleID(index), chapter.title, kind: .heading) }
            if includeAll || TranslationVisibility.readerNotes {
                add(chapterNotesID(index), chapter.notes)
                add(chapterEndNotesID(index), chapter.endNotes)
                if index == detail.chapters.count - 1 { add(endNotesID, detail.endNotes) }
            }
        }
        return result
    }

    /// 目前章節頂部（標題、簡介）需要翻譯的項目
    private var currentMeta: [Paragraph] {
        guard let detail else { return [] }
        return Self.metaParagraphs(detail: detail, chapters: [chapterIndex])
    }

    /// 章節頂部的標題區塊出現 / 消失（捲動模式）
    func headerAppeared() {
        for paragraph in currentMeta {
            visible.insert(paragraph.id)
            if isTranslationOn { enqueue(paragraph) }
        }
    }

    func headerDisappeared() {
        for paragraph in currentMeta { visible.remove(paragraph.id) }
    }

    /// 章節目錄：一次翻譯全部章節標題（譯文顯示在原標題下方）
    func translateChapterTitles() async {
        guard isTranslationOn, let detail, detail.chapters.count > 1 else { return }
        let pending = detail.chapters.indices.map(Self.chapterTitleID)
            .compactMap { id in translations[id] == nil ? lookup[id] : nil }
        guard !pending.isEmpty, let provider = try? settings.makeProvider() else { return }
        for paragraph in pending { translations[paragraph.id] = .loading }
        let generation = generation
        do {
            let results = try await translator.translate(paragraphs: pending, provider: provider,
                                                         source: settings.config.sourceLanguage, target: targetLanguage)
            guard generation == self.generation else { return }
            for (paragraph, text) in zip(pending, results) { translations[paragraph.id] = .done(text) }
        } catch {
            guard generation == self.generation else { return }
            for paragraph in pending { translations[paragraph.id] = .failed(error.localizedDescription) }
        }
    }

    func retryMeta(_ id: String) {
        guard let paragraph = lookup[id] else { return }
        retry(paragraph)
    }

    func paragraphAppeared(_ paragraph: Paragraph) {
        visible.insert(paragraph.id)
        guard isTranslationOn, let chapter else { return }
        enqueue(paragraph)
        if let index = chapter.paragraphs.firstIndex(of: paragraph) {
            for next in chapter.paragraphs.dropFirst(index + 1).prefix(prefetchCount) {
                enqueue(next)
            }
        }
    }

    func paragraphDisappeared(_ paragraph: Paragraph) {
        visible.remove(paragraph.id)
    }

    func setTargetLanguage(_ code: String) {
        guard code != settings.config.targetLanguageCode else { return }
        settings.config.targetLanguageCode = code
        resetTranslations(keepOffline: true)
    }

    func setSourceLanguage(_ code: String?) {
        guard code != settings.config.sourceLanguageCode else { return }
        settings.config.sourceLanguageCode = code
        resetTranslations()
    }

    var sourceLanguage: TranslationLanguage? { settings.config.sourceLanguage }

    /// 翻頁模式：以目前頁面上的段落取代可見集合（捲動模式則由 onAppear / onDisappear 維護）。
    func setVisibleParagraphs(_ paragraphs: [Paragraph]) {
        visible = Set(paragraphs.map(\.id))
        // 章節第一頁同時顯示標題
        if let first = chapter?.paragraphs.first, paragraphs.contains(first) || paragraphs.isEmpty {
            headerAppeared()
        }
        guard isTranslationOn else { return }
        for paragraph in paragraphs { paragraphAppeared(paragraph) }
    }

    func setDisplayMode(_ mode: BilingualDisplayMode) {
        settings.config.displayMode = mode
    }

    /// 清除目前譯文並以目前設定重新翻譯可見段落（切換語言、服務或手動重譯時）。
    func resetTranslations(keepOffline: Bool = false) {
        cancelPending()
        translations.removeAll()
        translationError = nil
        if keepOffline { applyOfflineTranslations() }
        if isTranslationOn { enqueueVisible() }
    }

    /// 使用者選擇的段落重新翻譯：略過翻譯快取，結果覆蓋舊譯文（含書架的離線譯文）
    func retry(_ paragraph: Paragraph) {
        translations[paragraph.id] = nil
        enqueue(paragraph)
    }

    /// 目前可見段落及其後預取範圍。
    private func wantedParagraphs() -> Set<Paragraph.ID> {
        guard let paragraphs = chapter?.paragraphs else { return [] }
        var wanted = Set(currentMeta.map(\.id).filter(visible.contains))
        for (index, paragraph) in paragraphs.enumerated() where visible.contains(paragraph.id) {
            for next in paragraphs[index..<min(index + prefetchCount + 1, paragraphs.count)] {
                wanted.insert(next.id)
            }
        }
        return wanted
    }

    private func enqueueVisible() {
        guard let chapter else { return }
        for paragraph in currentMeta where visible.contains(paragraph.id) { enqueue(paragraph) }
        for paragraph in chapter.paragraphs where visible.contains(paragraph.id) {
            paragraphAppeared(paragraph)
        }
    }

    private func enqueue(_ paragraph: Paragraph) {
        guard paragraph.isTranslatable, translations[paragraph.id] == nil else { return }
        translations[paragraph.id] = .loading
        queue.append(paragraph.id)
        scheduleFlush()
    }

    private func cancelPending() {
        generation += 1
        flushTask?.cancel()
        flushTask = nil
        // 包含已送出但結果會被丟棄的批次
        translations = translations.filter { $0.value != .loading }
        queue.removeAll()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let generation = generation
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.flush(generation: generation)
        }
    }

    private func flush(generation: Int) async {
        guard generation == self.generation else { return }

        let provider: any TranslationProvider
        do {
            provider = try settings.makeProvider()
        } catch {
            for id in queue { translations[id] = .failed(error.localizedDescription) }
            queue.removeAll()
            translationError = error.localizedDescription
            flushTask = nil
            return
        }

        // 快速捲動時一閃而過的段落不翻譯，等它再次出現時才重新排入，避免浪費請求與版面跳動
        let wanted = wantedParagraphs()
        for id in queue where !wanted.contains(id) { translations[id] = nil }
        queue.removeAll { !wanted.contains($0) }

        var batch: [Paragraph] = []
        var characters = 0
        while let id = queue.first {
            guard let paragraph = lookup[id] else { queue.removeFirst(); continue }
            if !batch.isEmpty, characters + paragraph.text.count > provider.maxBatchCharacters { break }
            batch.append(paragraph)
            characters += paragraph.text.count
            queue.removeFirst()
        }

        if !batch.isEmpty {
            do {
                let results = try await translator.translate(paragraphs: batch, provider: provider, source: settings.config.sourceLanguage, target: targetLanguage)
                guard generation == self.generation else { return }
                for (paragraph, text) in zip(batch, results) {
                    translations[paragraph.id] = .done(text)
                }
                translationError = nil
            } catch {
                guard generation == self.generation else { return }
                for paragraph in batch { translations[paragraph.id] = .failed(error.localizedDescription) }
                translationError = error.localizedDescription
                if case TranslationError.verificationRequired(let required) = error, challenge == nil,
                   presentedChallenges.insert(required.id).inserted {
                    challenge = required
                }
            }
        }

        flushTask = nil
        if !queue.isEmpty { scheduleFlush() }
    }
}
