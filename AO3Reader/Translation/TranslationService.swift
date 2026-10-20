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
    /// 再以冒號接回，避免翻譯服務偶爾吃掉冒號（「第三章历史与客观性」）。
    func translate(paragraphs: [Paragraph], provider: any TranslationProvider, source: TranslationLanguage?,
                   target: TranslationLanguage, bypassCache: Bool = false) async throws -> [String] {
        var texts: [String] = []
        var parts: [Int] = []
        for paragraph in paragraphs {
            if paragraph.id.hasPrefix("meta-title-c"), case let (number, title)? = Self.splitChapterTitle(paragraph.text) {
                texts += [number, title]
                parts.append(2)
            } else {
                texts.append(paragraph.text)
                parts.append(1)
            }
        }
        let translated = try await translate(texts, provider: provider, source: source, target: target, bypassCache: bypassCache)
        let separator = ["zh", "ja"].contains { target.code.hasPrefix($0) } ? "：" : ": "
        var results: [String] = []
        var index = 0
        for count in parts {
            guard index + count <= translated.count else { break }
            if count == 2 {
                let number = translated[index].trimmingCharacters(in: CharacterSet(charactersIn: ":： ").union(.whitespaces))
                results.append(number + separator + translated[index + 1].trimmingCharacters(in: .whitespaces))
            } else {
                results.append(translated[index])
            }
            index += count
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
}
