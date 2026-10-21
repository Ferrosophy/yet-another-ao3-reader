// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// 顯示譯文的開關（設定 › 一般）：作品名稱、Fandom、標籤、簡介可分別決定是否顯示譯文，
/// 瀏覽（作品列表與卡片）與閱讀頁各自一組。
enum TranslationVisibility {
    // 瀏覽頁與作品列表
    static let titleKey = "translate.show.title"
    static let fandomKey = "translate.show.fandom"
    static let tagsKey = "translate.show.tags"
    static let summaryKey = "translate.show.summary"
    // 閱讀頁
    static let readerTitleKey = "translate.reader.show.title"
    static let readerFandomKey = "translate.reader.show.fandom"
    static let readerSummaryKey = "translate.reader.show.summary"
    static let readerRatingKey = "translate.reader.show.rating"
    static let readerWarningKey = "translate.reader.show.warning"
    static let readerCategoryKey = "translate.reader.show.category"
    static let readerRelationshipKey = "translate.reader.show.relationship"
    static let readerCharacterKey = "translate.reader.show.character"
    static let readerFreeformKey = "translate.reader.show.freeform"
    static let readerNotesKey = "translate.reader.show.notes"

    private static func value(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    static var readerTitle: Bool { value(readerTitleKey) }
    static var readerSummary: Bool { value(readerSummaryKey) }
    static var readerNotes: Bool { value(readerNotesKey) }

    /// 閱讀頁某個標籤分組是否顯示譯文
    static func reader(_ group: WorkTagGroup) -> Bool {
        switch group.kind {
        case "rating": value(readerRatingKey)
        case "warning": value(readerWarningKey)
        case "category": value(readerCategoryKey)
        case "relationship": value(readerRelationshipKey)
        case "character": value(readerCharacterKey)
        case "freeform": value(readerFreeformKey)
        case "fandom": value(readerFandomKey)
        default: group.isFandom ? value(readerFandomKey) : value(readerFreeformKey)
        }
    }
}

/// 單一卡片欄位的翻譯狀態。每個欄位各自被觀察，譯文送達時只重繪對應的卡片，
/// 不會讓整個列表一起重繪（快速捲動時不卡頓）。
@MainActor
@Observable
final class TranslationSlot {
    var value: ParagraphTranslation?
}

/// 作品卡片的作品名稱與簡介翻譯（沉浸式：譯文顯示在原文下方，目標語言跟隨翻譯設定）。
///
/// 策略：
/// - 卡片出現時排入佇列，短暫防抖後合併成批次送出；卡片捲出畫面時，尚未送出的項目會取消
/// - 結果依欄位保存，換服務或語言後自動清空
@MainActor
@Observable
final class SummaryTranslator {
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    @ObservationIgnored private var slots: [String: TranslationSlot] = [:]
    @ObservationIgnored private let settings: TranslationSettings
    @ObservationIgnored private let translator: TranslationService
    @ObservationIgnored private var texts: [String: String] = [:]
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var signature = ""

    private static let enabledKey = "cards.translateSummary"

    init(settings: TranslationSettings, translator: TranslationService) {
        self.settings = settings
        self.translator = translator
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    static func summaryKey(_ id: Int) -> String { "s\(id)" }
    static func titleKey(_ id: Int) -> String { "t\(id)" }

    /// 取得欄位的翻譯狀態（不存在時建立；建立不會觸發重繪）
    func slot(_ key: String) -> TranslationSlot {
        if let slot = slots[key] { return slot }
        let slot = TranslationSlot()
        slots[key] = slot
        return slot
    }

    func request(_ key: String, text: String) {
        guard isEnabled, !text.isEmpty else { return }
        resetIfConfigChanged()
        let slot = slot(key)
        guard slot.value == nil else { return }
        texts[key] = text
        slot.value = .loading
        queue.append(key)
        scheduleFlush()
    }

    /// 卡片離開畫面：尚未送出的請求取消，下次出現時再排入
    func cancel(_ key: String) {
        guard let index = queue.firstIndex(of: key) else { return }
        queue.remove(at: index)
        slots[key]?.value = nil
    }

    func retry(_ key: String, text: String) {
        slots[key]?.value = nil
        request(key, text: text)
    }

    /// 卡片以此作為重新請求的依據（換服務或語言時改變）
    var currentSignature: String {
        let config = settings.config
        return "\(config.provider.rawValue)|\(config.sourceLanguageCode ?? "auto")|\(config.targetLanguageCode)"
    }

    private func resetIfConfigChanged() {
        let current = currentSignature
        guard current != signature else { return }
        signature = current
        for slot in slots.values { slot.value = nil }
        queue.removeAll()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            await self?.flush()
        }
    }

    private func flush() async {
        let signature = signature
        let provider: any TranslationProvider
        do {
            provider = try settings.makeProvider()
        } catch {
            for key in queue { slots[key]?.value = .failed(error.localizedDescription) }
            queue.removeAll()
            flushTask = nil
            return
        }

        var batch: [(String, String)] = []
        var characters = 0
        while let key = queue.first {
            queue.removeFirst()
            guard let text = texts[key] else { continue }
            if !batch.isEmpty, characters + text.count > provider.maxBatchCharacters {
                queue.insert(key, at: 0)
                break
            }
            batch.append((key, text))
            characters += text.count
        }

        if !batch.isEmpty {
            do {
                let translated = try await translator.translate(batch.map(\.1), provider: provider,
                                                                source: settings.config.sourceLanguage,
                                                                target: settings.config.targetLanguage)
                if signature == self.signature {
                    for ((key, _), text) in zip(batch, translated) { slots[key]?.value = .done(text) }
                }
            } catch {
                if signature == self.signature {
                    for (key, _) in batch { slots[key]?.value = .failed(error.localizedDescription) }
                }
            }
        }

        flushTask = nil
        if !queue.isEmpty { scheduleFlush() }
    }
}
