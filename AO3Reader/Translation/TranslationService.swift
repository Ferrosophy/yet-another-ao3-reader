// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

/// 帶快取的翻譯執行器。快取鍵 = 服務/模型 + 目標語言 + 原文，
/// 保存在 Caches 目錄（系統可在空間不足時清除），不離開本機。
actor TranslationService {
    private var memory: [String: String] = [:]
    private let directory: URL

    init() {
        directory = URL.cachesDirectory.appending(path: "Translations", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `bypassCache` 為 true 時忽略快取重新翻譯（使用者手動重譯某段），結果覆蓋舊快取
    func translate(_ texts: [String], provider: any TranslationProvider, source: TranslationLanguage?, target: TranslationLanguage,
                   bypassCache: Bool = false) async throws -> [String] {
        let keys = texts.map { cacheKey($0, provider: provider, source: source, target: target) }
        var results: [String?] = bypassCache ? keys.map { _ in nil } : keys.map(cached)

        let missing = results.indices.filter { results[$0] == nil }
        if !missing.isEmpty {
            let translated = try await provider.translate(missing.map { texts[$0] }, from: source, to: target)
            for (index, text) in zip(missing, translated) {
                results[index] = text
                store(text, for: keys[index])
            }
        }
        return results.map { $0 ?? "" }
    }

    func clearCache() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func cacheKey(_ text: String, provider: any TranslationProvider, source: TranslationLanguage?, target: TranslationLanguage) -> String {
        let digest = SHA256.hash(data: Data("\(provider.cacheIdentifier)|\(source?.code ?? "auto")|\(target.code)|\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cached(_ key: String) -> String? {
        if let hit = memory[key] { return hit }
        guard let data = try? Data(contentsOf: directory.appending(path: key)) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        memory[key] = text
        return text
    }

    private func store(_ text: String, for key: String) {
        memory[key] = text
        try? Data(text.utf8).write(to: directory.appending(path: key), options: .atomic)
    }
}

extension TranslationService {
    /// 翻譯段落。章節標題（例如「Chapter 3: History and Objectivity」）拆成編號與標題分別翻譯，
    /// 再以冒號接回，避免翻譯服務偶爾吃掉冒號（「第三章历史与客观性」）；章節編號一律使用阿拉伯數字。
    func translate(paragraphs: [Paragraph], provider: any TranslationProvider, source: TranslationLanguage?,
                   target: TranslationLanguage, bypassCache: Bool = false) async throws -> [String] {
        enum Part { case plain, split(local: String?), localOnly(String) }
        var texts: [String] = []
        var parts: [Part] = []
        for paragraph in paragraphs {
            guard paragraph.id.hasPrefix("meta-title-c") else {
                texts.append(paragraph.text)
                parts.append(.plain)
                continue
            }
            if case let (number, title)? = Self.splitChapterTitle(paragraph.text) {
                // 「Chapter 3」在中日韓語直接組成「第3章」，不交給翻譯服務
                let local = Self.localChapterNumber(number, target: target)
                if local == nil { texts.append(number) }
                texts.append(title)
                parts.append(.split(local: local))
            } else if let local = Self.localChapterNumber(paragraph.text, target: target) {
                parts.append(.localOnly(local))
            } else {
                texts.append(paragraph.text)
                parts.append(.plain)
            }
        }
        let translated = texts.isEmpty ? [] : try await translate(texts, provider: provider, source: source, target: target,
                                                                  bypassCache: bypassCache)
        let separator = ["zh", "ja"].contains { target.code.hasPrefix($0) } ? "：" : ": "
        var results: [String] = []
        var index = 0
        func next() -> String? {
            guard index < translated.count else { return nil }
            defer { index += 1 }
            return translated[index]
        }
        for part in parts {
            switch part {
            case .plain:
                guard let text = next() else { return results }
                results.append(text)
            case .localOnly(let local):
                results.append(local)
            case .split(let local):
                let number: String
                if let local {
                    number = local
                } else {
                    guard let text = next() else { return results }
                    number = Self.arabicNumerals(text.trimmingCharacters(in: CharacterSet(charactersIn: ":：").union(.whitespaces)))
                }
                guard let title = next() else { return results }
                results.append(number + separator + title.trimmingCharacters(in: .whitespaces))
            }
        }
        return results
    }

    /// 「Chapter 3: Title」→（「Chapter 3」,「Title」）；冒號前須以數字結尾
    static func splitChapterTitle(_ text: String) -> (String, String)? {
        guard let match = text.firstMatch(of: /^(.*?\d+)\s*[:：]\s*(.+)$/) else { return nil }
        let number = String(match.1).trimmingCharacters(in: .whitespaces)
        let title = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty, !title.isEmpty else { return nil }
        return (number, title)
    }

    /// 「Chapter 3」「Ch. 3」在中文、日文、韓文直接組成「第3章」「第3章」「제3장」；其他情況回傳 nil
    static func localChapterNumber(_ text: String, target: TranslationLanguage) -> String? {
        guard let match = text.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /(?i)(?:chapter|chap\.?|ch\.?)\s*(\d+)/) else { return nil }
        let number = String(match.1)
        if target.code.hasPrefix("zh") || target.code.hasPrefix("ja") { return "第\(number)章" }
        if target.code.hasPrefix("ko") { return "제\(number)장" }
        return nil
    }

    /// 把中文數字（三、二十三、一百零五）換成阿拉伯數字，只用於章節編號
    static func arabicNumerals(_ text: String) -> String {
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "兩": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
        var result = ""
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var total = 0
            var digit = 0
            for character in run {
                if let value = digits[character] {
                    digit = value
                } else if let unit = units[character] {
                    total += (digit == 0 ? 1 : digit) * unit
                    digit = 0
                }
            }
            result += String(total + digit)
            run = ""
        }
        for character in text {
            if digits[character] != nil || units[character] != nil {
                run.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }
}
