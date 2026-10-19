import Foundation
import Observation

/// 標籤翻譯：目標語言跟隨 App 介面語言（簡介與正文則跟隨翻譯設定的目標語言）。
/// 標籤多為短詞且大量重複，結果依標籤文字保存，並經 TranslationService 的磁碟快取。
@MainActor
@Observable
final class TagTranslator {
    private(set) var results: [String: String] = [:]

    private let settings: TranslationSettings
    private let translator: TranslationService
    private var requested: Set<String> = []
    private var queue: [String] = []
    private var flushTask: Task<Void, Never>?
    private var signature = ""

    init(settings: TranslationSettings, translator: TranslationService) {
        self.settings = settings
        self.translator = translator
    }

    /// 介面語言對應的翻譯語言
    static var targetLanguage: TranslationLanguage {
        let code = InterfaceLanguage.currentCode
        if code.hasPrefix("zh-Hant-HK") || code.hasPrefix("zh-Hant-MO") || code == "zh-HK" { return .named("zh-HK") }
        if code.hasPrefix("zh-Hant") || code == "zh-TW" { return .named("zh-TW") }
        if code.hasPrefix("zh") { return .named("zh-CN") }
        let base = String(code.prefix { $0 != "-" })
        return TranslationLanguage.lookup(base) ?? .named("en")
    }

    private var currentSignature: String { "\(settings.config.provider.rawValue)|\(Self.targetLanguage.code)" }

    /// 譯文與原文相同（例如英文介面看英文標籤）時回傳 nil，不重複顯示
    func translation(for tag: String) -> String? {
        guard signature == currentSignature, let result = results[tag],
              result.caseInsensitiveCompare(tag) != .orderedSame
        else { return nil }
        return result
    }

    func request(_ tags: [String]) {
        if signature != currentSignature {
            signature = currentSignature
            results.removeAll()
            requested.removeAll()
            queue.removeAll()
        }
        for tag in tags where !tag.isEmpty && requested.insert(tag).inserted {
            queue.append(tag)
        }
        guard !queue.isEmpty, flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.flush()
        }
    }

    private func flush() async {
        let signature = signature
        guard let provider = try? settings.makeProvider() else {
            queue.removeAll()
            flushTask = nil
            return
        }
        let batch = Array(queue.prefix(60))
        queue.removeFirst(batch.count)
        if let translated = try? await translator.translate(batch, provider: provider, source: nil, target: Self.targetLanguage),
           signature == self.signature {
            for (tag, text) in zip(batch, translated) { results[tag] = text }
        } else if signature == self.signature {
            // 失敗的標籤允許之後再次請求
            for tag in batch { requested.remove(tag) }
        }
        flushTask = nil
        if !queue.isEmpty {
            flushTask = Task { [weak self] in await self?.flush() }
        }
    }
}
