import Foundation
import Observation

/// 作品卡片的簡介翻譯（沉浸式：譯文顯示在簡介下方）。
/// 卡片出現時排入佇列，短暫防抖後合併成批次送出，結果依作品 ID 保存；
/// 換服務或語言後自動清空舊譯文。
@MainActor
@Observable
final class SummaryTranslator {
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private(set) var results: [Int: ParagraphTranslation] = [:]

    private let settings: TranslationSettings
    private let translator: TranslationService
    private var texts: [Int: String] = [:]
    private var queue: [Int] = []
    private var flushTask: Task<Void, Never>?
    private var signature = ""

    private static let enabledKey = "cards.translateSummary"

    init(settings: TranslationSettings, translator: TranslationService) {
        self.settings = settings
        self.translator = translator
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// 設定已變更（尚未重新請求）時不回傳舊譯文
    func translation(for id: Int) -> ParagraphTranslation? {
        signature == currentSignature ? results[id] : nil
    }

    func request(id: Int, summary: String) {
        guard isEnabled, !summary.isEmpty else { return }
        resetIfConfigChanged()
        guard results[id] == nil else { return }
        texts[id] = summary
        results[id] = .loading
        queue.append(id)
        scheduleFlush()
    }

    func retry(id: Int, summary: String) {
        results[id] = nil
        request(id: id, summary: summary)
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
        results.removeAll()
        queue.removeAll()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.flush()
        }
    }

    private func flush() async {
        let signature = signature
        let provider: any TranslationProvider
        do {
            provider = try settings.makeProvider()
        } catch {
            for id in queue { results[id] = .failed(error.localizedDescription) }
            queue.removeAll()
            flushTask = nil
            return
        }

        var batch: [(Int, String)] = []
        var characters = 0
        while let id = queue.first {
            queue.removeFirst()
            guard let text = texts[id] else { continue }
            if !batch.isEmpty, characters + text.count > provider.maxBatchCharacters {
                queue.insert(id, at: 0)
                break
            }
            batch.append((id, text))
            characters += text.count
        }

        if !batch.isEmpty {
            do {
                let translated = try await translator.translate(batch.map(\.1), provider: provider,
                                                                source: settings.config.sourceLanguage,
                                                                target: settings.config.targetLanguage)
                if signature == self.signature {
                    for ((id, _), text) in zip(batch, translated) { results[id] = .done(text) }
                }
            } catch {
                if signature == self.signature {
                    for (id, _) in batch { results[id] = .failed(error.localizedDescription) }
                }
            }
        }

        flushTask = nil
        if !queue.isEmpty { scheduleFlush() }
    }
}
