import Foundation

/// 各家大模型 API 的最小抽象：給定 system 與 user 文字，回傳模型輸出文字。
protocol ChatBackend: Sendable {
    var identifier: String { get }
    func complete(system: String, user: String) async throws -> String
}

/// 使用大模型進行段落對齊翻譯：輸入 JSON 字串陣列，要求輸出等長的 JSON 字串陣列。
/// 若模型回傳段數不符，會二分後重試，最終退化為逐段翻譯，確保每段原文都有對應譯文。
struct LLMTranslator: TranslationProvider {
    let backend: any ChatBackend
    /// 使用者在設定中填寫的額外指示（例如人名譯法對照表、文風要求）
    var extraInstructions = ""

    var cacheIdentifier: String {
        // 指示內容不同視為不同翻譯
        extraInstructions.isEmpty ? backend.identifier : "\(backend.identifier)#\(extraInstructions.hashValueStable)"
    }
    var maxBatchCharacters: Int { 6000 }

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        do {
            let output = try await backend.complete(
                system: LLMPrompt.system(source: source, target: target, extra: extraInstructions),
                user: try LLMPrompt.user(texts)
            )
            return try LLMPrompt.parse(output, expectedCount: texts.count)
        } catch TranslationError.countMismatch where texts.count > 1 {
            let middle = texts.count / 2
            async let head = translate(Array(texts[..<middle]), from: source, to: target)
            async let tail = translate(Array(texts[middle...]), from: source, to: target)
            return try await head + tail
        }
    }
}

enum LLMPrompt {
    static func system(source: TranslationLanguage? = nil, target: TranslationLanguage, extra: String) -> String {
        var prompt = """
        You are a professional literary translator working on fan fiction from Archive of Our Own (AO3).
        Translate every paragraph\(source.map { " from \($0.englishName)" } ?? "") into \(target.englishName) (\(target.code)).

        Rules:
        - Faithfully preserve meaning, tone, voice, humor and emotional nuance; write natural, fluent prose in the target language.
        - Keep character names, places and fandom-specific terms consistent across paragraphs.
        - Preserve line breaks inside a paragraph.
        - If a paragraph is already in the target language, or is only symbols, return it unchanged.
        - Do not add notes, explanations, or romanization.
        - The input is a JSON array of N strings. Respond with ONLY a JSON array of exactly N strings, in the same order.
        """
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            prompt += "\n\nAdditional instructions from the reader:\n\(extra)"
        }
        return prompt
    }

    static func user(_ texts: [String]) throws -> String {
        let data = try JSONEncoder().encode(texts)
        return String(decoding: data, as: UTF8.self)
    }

    /// 容忍 ```json 程式碼區塊或前後多餘文字，只取最外層的 JSON 陣列。
    static func parse(_ output: String, expectedCount: Int) throws -> [String] {
        guard let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]"), start < end else {
            throw TranslationError.malformedResponse(String(output.prefix(120)))
        }
        let json = output[start...end]
        guard let array = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else {
            throw TranslationError.malformedResponse(String(json.prefix(120)))
        }
        guard array.count == expectedCount else {
            throw TranslationError.countMismatch(expected: expectedCount, got: array.count)
        }
        return array
    }
}

extension String {
    /// 跨啟動穩定的雜湊（Swift 的 hashValue 每次啟動都不同，不能用於持久化快取鍵）
    var hashValueStable: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
