// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// 作者在標籤、簡介或作者註中聲明「不要翻譯」「不要用於 AI」時，App 預設不翻譯這部作品：
/// 閱讀頁需使用者確認才翻譯，且不使用 AI（大型語言模型）服務；離線保存不自動翻譯。
enum AuthorWishes {
    private static let patterns: [String] = [
        // English
        #"\bno\s*a\.?i\.?\b"#,
        #"\bnot\s+for\s+a\.?i\b"#,
        #"\bdo\s*n[o']?t\s+(feed|use|upload|put|run)\b[^.\n]{0,40}\b(a\.?i|chat\s*gpt|llm|machine)\b"#,
        #"\b(a\.?i|llm)\s+(training|scraping|learning)\b"#,
        #"\bdo\s*n[o']?t\s+translate\b"#,
        #"\bno\s+(machine\s+)?translations?\b"#,
        #"\btranslations?\s+(are\s+)?not\s+(allowed|permitted)\b"#,
        #"\bwithout\s+(my\s+)?permission\b[^.\n]{0,40}\btranslat"#,
        // 中文
        #"(禁止|拒绝|拒絕|請勿|请勿|不要|不許|不许|謝絕|谢绝)[^。\n]{0,6}(翻譯|翻译|喂\s*AI|餵\s*AI|投喂|AI|機翻|机翻)"#,
        // 日本語・한국어
        #"(翻訳|無断翻訳|AI学習|AI\s*学習)[^。\n]{0,4}禁止"#,
        #"번역\s*금지"#,
    ]

    private static let regexes: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    /// 找到作者的聲明時回傳所在的句子（顯示給使用者），否則 nil
    static func declinesTranslation(_ texts: [String]) -> String? {
        for text in texts where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for regex in regexes {
                guard let match = regex.firstMatch(in: text, range: range), let found = Range(match.range, in: text) else { continue }
                return sentence(around: found, in: text)
            }
        }
        return nil
    }

    /// 作品的標籤、簡介與各章作者註
    static func declinesTranslation(_ detail: WorkDetail) -> String? {
        var texts = detail.tagGroups.flatMap { $0.tags.map(\.name) }
        texts += [detail.summary, detail.notes, detail.endNotes]
        for chapter in detail.chapters { texts += [chapter.notes, chapter.endNotes] }
        return declinesTranslation(texts)
    }

    /// 擷取比對位置所在的句子（最多約 160 字）
    private static func sentence(around range: Range<String.Index>, in text: String) -> String {
        let stops: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]
        var start = range.lowerBound
        while start > text.startIndex, !stops.contains(text[text.index(before: start)]) { start = text.index(before: start) }
        var end = range.upperBound
        while end < text.endIndex, !stops.contains(text[end]) { end = text.index(after: end) }
        if end < text.endIndex { end = text.index(after: end) }
        let sentence = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.count > 160 ? String(sentence.prefix(160)) + "…" : sentence
    }
}
