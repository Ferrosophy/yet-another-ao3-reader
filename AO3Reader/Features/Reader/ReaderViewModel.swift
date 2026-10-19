import Foundation
import Observation

enum ParagraphTranslation: Equatable, Sendable {
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
    private(set) var translations: [Paragraph.ID: ParagraphTranslation] = [:]
    private(set) var translationError: String?

    var isTranslationOn = false {
        didSet {
            guard isTranslationOn != oldValue else { return }
            if isTranslationOn { enqueueVisible() } else { cancelPending() }
        }
    }

    private let client: AO3Client
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

    var hasPrevious: Bool { chapterIndex > 0 }
    var hasNext: Bool { chapterIndex + 1 < (detail?.chapters.count ?? 0) }
    var targetLanguage: TranslationLanguage { settings.config.targetLanguage }
    var displayMode: BilingualDisplayMode { settings.config.displayMode }

    // MARK: - Loading

    func load() async {
        guard detail == nil else { return }
        do {
            let detail = try await client.work(id: route.id)
            for chapter in detail.chapters {
                for paragraph in chapter.paragraphs { lookup[paragraph.id] = paragraph }
            }
            let saved = UserDefaults.standard.integer(forKey: positionKey)
            chapterIndex = min(max(saved, 0), detail.chapters.count - 1)
            self.detail = detail
        } catch AO3Error.requiresLogin {
            requiresLogin = true
            loadError = AO3Error.requiresLogin.localizedDescription
        } catch {
            loadError = error.localizedDescription
        }
    }

    private var positionKey: String { "reader.position.\(route.id)" }

    // MARK: - Chapters

    func goToChapter(_ index: Int) {
        guard let detail, detail.chapters.indices.contains(index) else { return }
        chapterIndex = index
        visible.removeAll()
        UserDefaults.standard.set(index, forKey: positionKey)
    }

    func nextChapter() { goToChapter(chapterIndex + 1) }
    func previousChapter() { goToChapter(chapterIndex - 1) }

    // MARK: - Immersive translation

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
        resetTranslations()
    }

    func setDisplayMode(_ mode: BilingualDisplayMode) {
        settings.config.displayMode = mode
    }

    /// 清除目前譯文並以目前設定重新翻譯可見段落（切換語言、服務或手動重譯時）。
    func resetTranslations() {
        cancelPending()
        translations.removeAll()
        translationError = nil
        if isTranslationOn { enqueueVisible() }
    }

    func retry(_ paragraph: Paragraph) {
        translations[paragraph.id] = nil
        enqueue(paragraph)
    }

    private func enqueueVisible() {
        guard let chapter else { return }
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
                let results = try await translator.translate(batch.map(\.text), provider: provider, target: targetLanguage)
                guard generation == self.generation else { return }
                for (paragraph, text) in zip(batch, results) {
                    translations[paragraph.id] = .done(text)
                }
                translationError = nil
            } catch {
                guard generation == self.generation else { return }
                for paragraph in batch { translations[paragraph.id] = .failed(error.localizedDescription) }
                translationError = error.localizedDescription
            }
        }

        flushTask = nil
        if !queue.isEmpty { scheduleFlush() }
    }
}
