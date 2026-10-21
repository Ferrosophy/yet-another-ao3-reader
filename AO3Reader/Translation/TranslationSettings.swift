// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

enum TranslationProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case googleWeb, bingFree, apple, deepL, transmart, volcano, baiduWeb, youdaoWeb, sogouWeb
    case googleCloud, microsoftAzure, openAICompatible, anthropic, gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .googleWeb: String(localized: "Google 翻譯（免金鑰）")
        case .bingFree: String(localized: "Bing 翻譯（免金鑰）")
        case .apple: String(localized: "Apple 翻譯（裝置上）")
        case .deepL: "DeepL"
        case .transmart: String(localized: "騰訊交互翻譯 TranSmart（免金鑰）")
        case .volcano: String(localized: "火山翻譯（免金鑰）")
        case .baiduWeb: String(localized: "百度翻譯（網頁版）")
        case .youdaoWeb: String(localized: "有道翻譯（網頁版）")
        case .sogouWeb: String(localized: "搜狗翻譯（網頁版）")
        case .googleCloud: "Google Cloud Translation"
        case .microsoftAzure: "Microsoft Translator（Azure）"
        case .openAICompatible: String(localized: "OpenAI 相容 API")
        case .anthropic: "Anthropic Claude"
        case .gemini: "Google Gemini"
        }
    }

    var requiresAPIKey: Bool { [.googleCloud, .microsoftAzure, .openAICompatible, .anthropic, .gemini].contains(self) }
    /// 可填可不填金鑰（DeepL：填了走官方 API，不填走網頁版）
    var acceptsAPIKey: Bool { requiresAPIKey || self == .deepL }
    var isLLM: Bool { [.openAICompatible, .anthropic, .gemini].contains(self) }
    var keychainAccount: String { "apikey.\(rawValue)" }
}

/// 閱讀器中原文與譯文的呈現方式。
enum BilingualDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case bilingual, translationOnly

    var id: String { rawValue }
    var title: String { self == .bilingual ? String(localized: "原文與譯文") : String(localized: "僅譯文") }
}

/// 除 API Key 以外的翻譯設定（Key 只存在鑰匙圈）。
struct TranslationConfig: Codable, Equatable, Sendable {
    var provider: TranslationProviderKind = .googleWeb
    var targetLanguageCode = Locale.preferredLanguages.first.map(TranslationConfig.matchLanguage) ?? "zh-TW"
    var displayMode: BilingualDisplayMode = .bilingual
    var openAIBaseURL = "https://api.openai.com/v1"
    var openAIModel = ""
    var anthropicModel = "claude-sonnet-5-5"
    var geminiModel = "gemini-2.5-flash"
    var extraInstructions = ""
    /// nil 為自動偵測原文語言（新增欄位皆為 Optional，舊設定可正常解碼）
    var sourceLanguageCode: String?
    var azureRegion: String?

    var targetLanguage: TranslationLanguage { .named(targetLanguageCode) }
    var sourceLanguage: TranslationLanguage? { sourceLanguageCode.flatMap(TranslationLanguage.lookup) }

    private static func matchLanguage(_ preferred: String) -> String {
        if preferred.hasPrefix("zh-Hans") { return "zh-CN" }
        if preferred.hasPrefix("zh-Hant-HK") { return "zh-HK" }
        if preferred.hasPrefix("zh") { return "zh-TW" }
        let base = String(preferred.prefix { $0 != "-" })
        return TranslationLanguage.all.contains { $0.code == base } ? base : "en"
    }
}

/// OpenAI 相容服務的常用預設位址。
struct OpenAIPreset: Identifiable, Hashable {
    let name: String
    let baseURL: String
    var id: String { baseURL }

    static let all: [OpenAIPreset] = [
        .init(name: "OpenAI", baseURL: "https://api.openai.com/v1"),
        .init(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1"),
        .init(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1"),
        .init(name: "Groq", baseURL: "https://api.groq.com/openai/v1"),
    ]
}

@MainActor
@Observable
final class TranslationSettings {
    var config: TranslationConfig {
        didSet {
            // 換服務後原文語言不在支援範圍內時改回自動偵測
            if let code = config.sourceLanguageCode, !config.provider.supportsSource(code) {
                config.sourceLanguageCode = nil
                return
            }
            if config != oldValue { save() }
        }
    }

    private let defaults: UserDefaults
    private static let key = "translation.config"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.config = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(TranslationConfig.self, from: $0) } ?? TranslationConfig()
    }

    // MARK: - API keys（僅鑰匙圈）

    func apiKey(for kind: TranslationProviderKind) -> String {
        KeychainStore.read(account: kind.keychainAccount) ?? ""
    }

    func setAPIKey(_ key: String, for kind: TranslationProviderKind) throws {
        try KeychainStore.save(key, account: kind.keychainAccount)
    }

    func hasAPIKey(for kind: TranslationProviderKind) -> Bool {
        !apiKey(for: kind).isEmpty
    }

    // MARK: - Provider factory

    func makeProvider() throws -> any TranslationProvider {
        try makeProvider(for: config)
    }

    func makeProvider(for config: TranslationConfig) throws -> any TranslationProvider {
        let kind = config.provider
        let key = apiKey(for: kind)
        // OpenAI 相容服務允許無金鑰（例如本機 Ollama）
        if kind.requiresAPIKey, kind != .openAICompatible, key.isEmpty {
            throw TranslationError.missingAPIKey(kind.title)
        }
        switch kind {
        case .googleWeb:
            return GoogleWebTranslator()
        case .bingFree:
            return BingTranslator(auth: .edgeFree)
        case .apple:
            return AppleTranslator()
        case .deepL:
            return DeepLTranslator(apiKey: key)
        case .transmart:
            return TransmartTranslator()
        case .volcano:
            return VolcanoTranslator()
        case .baiduWeb:
            return BaiduWebTranslator()
        case .youdaoWeb:
            return YoudaoWebTranslator()
        case .sogouWeb:
            return SogouWebTranslator()
        case .googleCloud:
            return GoogleCloudTranslator(apiKey: key)
        case .microsoftAzure:
            return BingTranslator(auth: .azure(key: key, region: config.azureRegion ?? ""))
        case .openAICompatible:
            guard let url = URL(string: config.openAIBaseURL.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
                throw TranslationError.invalidBaseURL
            }
            let model = config.openAIModel.trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else { throw TranslationError.missingModel }
            return LLMTranslator(backend: OpenAICompatibleBackend(baseURL: url, apiKey: key, model: model),
                                 extraInstructions: config.extraInstructions)
        case .anthropic:
            return LLMTranslator(backend: AnthropicBackend(apiKey: key, model: config.anthropicModel),
                                 extraInstructions: config.extraInstructions)
        case .gemini:
            return LLMTranslator(backend: GeminiBackend(apiKey: key, model: config.geminiModel),
                                 extraInstructions: config.extraInstructions)
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(config), forKey: Self.key)
    }
}
