import Foundation

/// 翻譯語言。`code` 為 BCP-47，Google 與各 AI 模型皆可直接使用；其他服務在各自的翻譯器中轉換代碼。
struct TranslationLanguage: Identifiable, Hashable, Codable, Sendable {
    let code: String
    /// 該語言的自稱，同時提供給 AI 作為目標語言描述
    let name: String
    /// 給 AI 的英文描述，避免模型誤解（例如繁簡中文）
    let englishName: String

    var id: String { code }

    /// 以介面語言顯示的名稱（中文變體使用自訂名稱以區分繁簡）
    var displayName: String {
        if code.hasPrefix("zh") { return name }
        return Locale.current.localizedString(forIdentifier: code).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? englishName
    }

    /// 常用目標語言
    static let all: [TranslationLanguage] = [
        "zh-TW", "zh-HK", "zh-CN", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru",
        "uk", "pl", "tr", "vi", "th", "id", "ar",
    ].map(named)

    /// 完整語言目錄（原文語言選單與名稱查詢用）
    static let catalog: [TranslationLanguage] = [
        .init(code: "zh-TW", name: "繁體中文", englishName: "Traditional Chinese (Taiwan)"),
        .init(code: "zh-HK", name: "繁體中文（香港）", englishName: "Traditional Chinese (Hong Kong)"),
        .init(code: "zh-CN", name: "简体中文", englishName: "Simplified Chinese"),
        .init(code: "yue", name: "粵語", englishName: "Cantonese"),
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
        .init(code: "af", name: "Afrikaans", englishName: "Afrikaans"),
        .init(code: "sq", name: "Shqip", englishName: "Albanian"),
        .init(code: "am", name: "አማርኛ", englishName: "Amharic"),
        .init(code: "hy", name: "Հայերեն", englishName: "Armenian"),
        .init(code: "az", name: "Azərbaycan", englishName: "Azerbaijani"),
        .init(code: "eu", name: "Euskara", englishName: "Basque"),
        .init(code: "be", name: "Беларуская", englishName: "Belarusian"),
        .init(code: "bn", name: "বাংলা", englishName: "Bengali"),
        .init(code: "bs", name: "Bosanski", englishName: "Bosnian"),
        .init(code: "bg", name: "Български", englishName: "Bulgarian"),
        .init(code: "my", name: "မြန်မာ", englishName: "Burmese"),
        .init(code: "ca", name: "Català", englishName: "Catalan"),
        .init(code: "ceb", name: "Cebuano", englishName: "Cebuano"),
        .init(code: "co", name: "Corsu", englishName: "Corsican"),
        .init(code: "hr", name: "Hrvatski", englishName: "Croatian"),
        .init(code: "cs", name: "Čeština", englishName: "Czech"),
        .init(code: "da", name: "Dansk", englishName: "Danish"),
        .init(code: "nl", name: "Nederlands", englishName: "Dutch"),
        .init(code: "eo", name: "Esperanto", englishName: "Esperanto"),
        .init(code: "et", name: "Eesti", englishName: "Estonian"),
        .init(code: "tl", name: "Filipino", englishName: "Filipino"),
        .init(code: "fi", name: "Suomi", englishName: "Finnish"),
        .init(code: "fy", name: "Frysk", englishName: "Frisian"),
        .init(code: "gl", name: "Galego", englishName: "Galician"),
        .init(code: "ka", name: "ქართული", englishName: "Georgian"),
        .init(code: "el", name: "Ελληνικά", englishName: "Greek"),
        .init(code: "gu", name: "ગુજરાતી", englishName: "Gujarati"),
        .init(code: "ht", name: "Kreyòl ayisyen", englishName: "Haitian Creole"),
        .init(code: "ha", name: "Hausa", englishName: "Hausa"),
        .init(code: "haw", name: "ʻŌlelo Hawaiʻi", englishName: "Hawaiian"),
        .init(code: "he", name: "עברית", englishName: "Hebrew"),
        .init(code: "hi", name: "हिन्दी", englishName: "Hindi"),
        .init(code: "hmn", name: "Hmoob", englishName: "Hmong"),
        .init(code: "hu", name: "Magyar", englishName: "Hungarian"),
        .init(code: "is", name: "Íslenska", englishName: "Icelandic"),
        .init(code: "ig", name: "Igbo", englishName: "Igbo"),
        .init(code: "ga", name: "Gaeilge", englishName: "Irish"),
        .init(code: "jv", name: "Basa Jawa", englishName: "Javanese"),
        .init(code: "kn", name: "ಕನ್ನಡ", englishName: "Kannada"),
        .init(code: "kk", name: "Қазақ", englishName: "Kazakh"),
        .init(code: "km", name: "ខ្មែរ", englishName: "Khmer"),
        .init(code: "rw", name: "Kinyarwanda", englishName: "Kinyarwanda"),
        .init(code: "ku", name: "Kurdî", englishName: "Kurdish"),
        .init(code: "ky", name: "Кыргызча", englishName: "Kyrgyz"),
        .init(code: "lo", name: "ລາວ", englishName: "Lao"),
        .init(code: "la", name: "Latina", englishName: "Latin"),
        .init(code: "lv", name: "Latviešu", englishName: "Latvian"),
        .init(code: "lt", name: "Lietuvių", englishName: "Lithuanian"),
        .init(code: "lb", name: "Lëtzebuergesch", englishName: "Luxembourgish"),
        .init(code: "mk", name: "Македонски", englishName: "Macedonian"),
        .init(code: "mg", name: "Malagasy", englishName: "Malagasy"),
        .init(code: "ms", name: "Bahasa Melayu", englishName: "Malay"),
        .init(code: "ml", name: "മലയാളം", englishName: "Malayalam"),
        .init(code: "mt", name: "Malti", englishName: "Maltese"),
        .init(code: "mi", name: "Māori", englishName: "Maori"),
        .init(code: "mr", name: "मराठी", englishName: "Marathi"),
        .init(code: "mn", name: "Монгол", englishName: "Mongolian"),
        .init(code: "ne", name: "नेपाली", englishName: "Nepali"),
        .init(code: "no", name: "Norsk", englishName: "Norwegian"),
        .init(code: "ny", name: "Chichewa", englishName: "Nyanja"),
        .init(code: "or", name: "ଓଡ଼ିଆ", englishName: "Odia"),
        .init(code: "ps", name: "پښتو", englishName: "Pashto"),
        .init(code: "fa", name: "فارسی", englishName: "Persian"),
        .init(code: "pa", name: "ਪੰਜਾਬੀ", englishName: "Punjabi"),
        .init(code: "ro", name: "Română", englishName: "Romanian"),
        .init(code: "sm", name: "Gagana Samoa", englishName: "Samoan"),
        .init(code: "gd", name: "Gàidhlig", englishName: "Scottish Gaelic"),
        .init(code: "sr", name: "Српски", englishName: "Serbian"),
        .init(code: "st", name: "Sesotho", englishName: "Sesotho"),
        .init(code: "sn", name: "chiShona", englishName: "Shona"),
        .init(code: "sd", name: "سنڌي", englishName: "Sindhi"),
        .init(code: "si", name: "සිංහල", englishName: "Sinhala"),
        .init(code: "sk", name: "Slovenčina", englishName: "Slovak"),
        .init(code: "sl", name: "Slovenščina", englishName: "Slovenian"),
        .init(code: "so", name: "Soomaali", englishName: "Somali"),
        .init(code: "su", name: "Basa Sunda", englishName: "Sundanese"),
        .init(code: "sw", name: "Kiswahili", englishName: "Swahili"),
        .init(code: "sv", name: "Svenska", englishName: "Swedish"),
        .init(code: "tg", name: "Тоҷикӣ", englishName: "Tajik"),
        .init(code: "ta", name: "தமிழ்", englishName: "Tamil"),
        .init(code: "tt", name: "Татар", englishName: "Tatar"),
        .init(code: "te", name: "తెలుగు", englishName: "Telugu"),
        .init(code: "tk", name: "Türkmen", englishName: "Turkmen"),
        .init(code: "ur", name: "اردو", englishName: "Urdu"),
        .init(code: "ug", name: "ئۇيغۇرچە", englishName: "Uyghur"),
        .init(code: "uz", name: "Oʻzbek", englishName: "Uzbek"),
        .init(code: "cy", name: "Cymraeg", englishName: "Welsh"),
        .init(code: "xh", name: "isiXhosa", englishName: "Xhosa"),
        .init(code: "yi", name: "ייִדיש", englishName: "Yiddish"),
        .init(code: "yo", name: "Yorùbá", englishName: "Yoruba"),
        .init(code: "zu", name: "isiZulu", englishName: "Zulu"),
    ]

    private static let byCode = Dictionary(uniqueKeysWithValues: catalog.map { ($0.code, $0) })

    static func named(_ code: String) -> TranslationLanguage {
        byCode[code] ?? byCode["zh-TW"]!
    }

    static func lookup(_ code: String) -> TranslationLanguage? { byCode[code] }

    /// 可作為原文語言的目錄（香港繁體與台灣繁體在原文端無差別，只保留一個）
    static let sourceCatalog: [TranslationLanguage] = catalog.filter { $0.code != "zh-HK" }

    /// 是否符合搜尋字串（介面名稱、自稱、英文名或代碼）
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [displayName, name, englishName, code].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

extension TranslationProviderKind {
    /// 該服務可指定的原文語言代碼；nil 表示支援完整目錄。
    private var supportedSourceCodes: Set<String>? {
        switch self {
        case .googleWeb, .googleCloud, .openAICompatible, .anthropic, .gemini:
            nil
        case .bingFree, .microsoftAzure:
            Set(TranslationLanguage.sourceCatalog.map(\.code))
                .subtracting(["ceb", "co", "eo", "fy", "haw", "hmn", "jv", "la", "su", "yi", "gd", "ny", "sn", "st"])
        case .apple:
            ["zh-CN", "zh-TW", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "uk", "pl", "tr", "vi", "th", "id",
             "ar", "hi", "nl"]
        case .deepL:
            ["zh-CN", "zh-TW", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "uk", "pl", "tr", "id", "ar", "bg",
             "cs", "da", "nl", "et", "fi", "el", "hu", "lv", "lt", "no", "ro", "sk", "sl", "sv"]
        case .transmart:
            ["zh-CN", "zh-TW", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "tr", "vi", "th", "id", "ms", "ar", "hi"]
        case .volcano:
            ["zh-CN", "zh-TW", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "uk", "pl", "tr", "vi", "th", "id",
             "ar", "ms", "hi", "bn", "nl", "sv", "fi", "da", "no", "cs", "ro", "hu", "el", "bg", "hr", "sr", "sk", "sl",
             "lt", "lv", "et", "he", "fa", "ur", "ta", "te", "mr", "km", "lo", "my", "mn", "tl", "sw"]
        case .baiduWeb:
            ["zh-CN", "zh-TW", "yue", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "pl", "vi", "th", "ar", "el",
             "nl", "bg", "et", "da", "fi", "cs", "ro", "sl", "sv", "hu"]
        case .youdaoWeb:
            ["en", "ja", "ko", "fr", "ru", "es"]
        case .sogouWeb:
            ["zh-CN", "zh-TW", "en", "ja", "ko", "fr", "de", "es", "pt", "it", "ru", "uk", "pl", "tr", "vi", "th", "id",
             "ar", "ms", "hi", "nl", "sv", "fi", "da", "no", "cs", "hu", "el", "ro", "bg", "he"]
        }
    }

    /// 原文語言選單的選項：常用語言在前，其餘依介面語言的名稱排序
    var sourceLanguages: [TranslationLanguage] {
        let pool = TranslationLanguage.sourceCatalog.filter { supportedSourceCodes?.contains($0.code) ?? true }
        let common = Set(TranslationLanguage.all.map(\.code))
        let head = pool.filter { common.contains($0.code) }
        let tail = pool.filter { !common.contains($0.code) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return head + tail
    }

    func supportsSource(_ code: String) -> Bool {
        code != "zh-HK" && (supportedSourceCodes?.contains(code) ?? (TranslationLanguage.lookup(code) != nil))
    }
}
