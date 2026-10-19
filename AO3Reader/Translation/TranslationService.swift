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

    func translate(_ texts: [String], provider: any TranslationProvider, source: TranslationLanguage?, target: TranslationLanguage) async throws -> [String] {
        let keys = texts.map { cacheKey($0, provider: provider, source: source, target: target) }
        var results = keys.map(cached)

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
