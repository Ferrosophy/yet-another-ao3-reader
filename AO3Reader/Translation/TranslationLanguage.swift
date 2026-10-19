import Foundation

/// 翻譯目標語言。`code` 為 BCP-47，Google 與各 AI 模型皆可直接使用。
struct TranslationLanguage: Identifiable, Hashable, Codable, Sendable {
    let code: String
    /// 該語言的自稱，同時提供給 AI 作為目標語言描述
    let name: String
    /// 給 AI 的英文描述，避免模型誤解（例如繁簡中文）
    let englishName: String

    var id: String { code }

    static let all: [TranslationLanguage] = [
        .init(code: "zh-TW", name: "繁體中文", englishName: "Traditional Chinese (Taiwan)"),
        .init(code: "zh-HK", name: "繁體中文（香港）", englishName: "Traditional Chinese (Hong Kong)"),
        .init(code: "zh-CN", name: "简体中文", englishName: "Simplified Chinese"),
        .init(code: "en", name: "English", englishName: "English"),
        .init(code: "ja", name: "日本語", englishName: "Japanese"),
        .init(code: "ko", name: "한국어", englishName: "Korean"),
        .init(code: "fr", name: "Français", englishName: "French"),
        .init(code: "de", name: "Deutsch", englishName: "German"),
        .init(code: "es", name: "Español", englishName: "Spanish"),
        .init(code: "pt", name: "Português", englishName: "Portuguese"),
        .init(code: "it", name: "Italiano", englishName: "Italian"),
        .init(code: "ru", name: "Русский", englishName: "Russian"),
        .init(code: "uk", name: "Українська", englishName: "Ukrainian"),
        .init(code: "pl", name: "Polski", englishName: "Polish"),
        .init(code: "tr", name: "Türkçe", englishName: "Turkish"),
        .init(code: "vi", name: "Tiếng Việt", englishName: "Vietnamese"),
        .init(code: "th", name: "ไทย", englishName: "Thai"),
        .init(code: "id", name: "Bahasa Indonesia", englishName: "Indonesian"),
        .init(code: "ar", name: "العربية", englishName: "Arabic"),
    ]

    static func named(_ code: String) -> TranslationLanguage {
        all.first { $0.code == code } ?? all[0]
    }
}
