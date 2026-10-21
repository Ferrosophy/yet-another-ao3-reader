// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// 標籤翻譯：目標語言跟隨 App 介面語言（簡介與正文則跟隨翻譯設定的目標語言）。
///
/// 效能：
/// - 分級、警告、分類等固定標籤使用內建的 20 種語言翻譯，不需連線
/// - 其餘標籤合併成一段文字（每行一個）一次送出，避免每個標籤各發一個請求
/// - 結果保存在 Caches，App 重開後直接使用；每批只更新一次狀態，減少列表重繪
@MainActor
@Observable
final class TagTranslator {
    private(set) var results: [String: String]

    @ObservationIgnored private let settings: TranslationSettings
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    /// 介面語言對應的翻譯語言（介面語言需重開 App 才會改變，所以只計算一次）
    nonisolated static let targetLanguage: TranslationLanguage = {
        let code = InterfaceLanguage.currentCode
        if code.hasPrefix("zh-Hant-HK") || code.hasPrefix("zh-Hant-MO") || code == "zh-HK" { return .named("zh-HK") }
        if code.hasPrefix("zh-Hant") || code == "zh-TW" { return .named("zh-TW") }
        if code.hasPrefix("zh") { return .named("zh-CN") }
        let base = String(code.prefix { $0 != "-" })
        return TranslationLanguage.lookup(base) ?? .named("en")
    }()

    /// 內建的固定標籤翻譯：英文標籤 → 語言代碼 → 譯文
    nonisolated private static let fixed: [String: String] = {
        guard let url = Bundle.main.url(forResource: "FixedTags", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        let code = targetLanguage.code
        return table.compactMapValues { $0[code] }
    }()

    nonisolated private static var cacheURL: URL {
        URL.cachesDirectory.appending(path: "tag-translations-\(targetLanguage.code).json")
    }

    init(settings: TranslationSettings, translator _: TranslationService) {
        self.settings = settings
        results = (try? Data(contentsOf: Self.cacheURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// 譯文與原文相同（例如英文介面看英文標籤）時回傳 nil，不重複顯示
    func translation(for tag: String) -> String? {
        guard let result = Self.fixed[tag] ?? results[tag], result.caseInsensitiveCompare(tag) != .orderedSame else { return nil }
        return result
    }

    func request(_ tags: [String]) {
        guard Self.targetLanguage.code != "en" || tags.contains(where: { !$0.allSatisfy(\.isASCII) }) else { return }
        for tag in tags where !tag.isEmpty && Self.fixed[tag] == nil && results[tag] == nil && requested.insert(tag).inserted {
            queue.append(tag)
        }
        guard !queue.isEmpty, flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.flush()
        }
    }

    private func flush() async {
        guard let provider = try? settings.makeProvider() else {
            queue.removeAll()
            requested.removeAll()
            flushTask = nil
            return
        }
        let batch = Array(queue.prefix(80))
        queue.removeFirst(batch.count)
        let target = Self.targetLanguage

        var translated: [String]?
        // 一次送出整批（每行一個標籤）；行數對不上時才改為逐項
        if let joined = try? await provider.translate([batch.joined(separator: "\n")], from: nil, to: target).first {
            let lines = joined.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.count == batch.count { translated = lines }
        }
        if translated == nil {
            translated = try? await provider.translate(batch, from: nil, to: target)
        }

        if let translated, translated.count == batch.count {
            var updated = results
            for (tag, text) in zip(batch, translated) where !text.isEmpty { updated[tag] = text }
            results = updated
            let data = try? JSONEncoder().encode(updated)
            let url = Self.cacheURL
            Task.detached(priority: .utility) { try? data?.write(to: url, options: .atomic) }
        } else {
            // 失敗的標籤允許之後再次請求
            for tag in batch { requested.remove(tag) }
        }
        flushTask = nil
        if !queue.isEmpty {
            flushTask = Task { [weak self] in await self?.flush() }
        }
    }
}
