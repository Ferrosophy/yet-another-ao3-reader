import Foundation
import SwiftUI
import Translation

/// Apple 翻譯（系統內建）：在裝置上翻譯，免金鑰、可離線。
/// 語言包未下載時拋出 `appleDownload` 挑戰，由介面彈出系統的下載視窗。
struct AppleTranslator: TranslationProvider {
    var cacheIdentifier: String { "apple" }
    var maxBatchCharacters: Int { 6000 }

    func translate(_ texts: [String], from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> [String] {
        let source = source ?? WebTranslation.detect(texts) ?? .named("en")
        let from = Self.language(source)
        let to = Self.language(target)

        switch await LanguageAvailability().status(from: from, to: to) {
        case .installed:
            break
        case .supported:
            throw TranslationError.verificationRequired(.appleDownload(source: source.code, target: target.code))
        case .unsupported:
            throw TranslationError.unsupportedLanguage(String(localized: "Apple 翻譯不支援這組語言"))
        @unknown default:
            throw TranslationError.unsupportedLanguage(String(localized: "Apple 翻譯不支援這組語言"))
        }

        let session = TranslationSession(installedSource: from, target: to)
        let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
        let responses = try await session.translations(from: requests)
        var results = Array(repeating: "", count: texts.count)
        for response in responses {
            if let index = response.clientIdentifier.flatMap(Int.init), results.indices.contains(index) {
                results[index] = response.targetText
            }
        }
        return results
    }

    static func language(_ language: TranslationLanguage) -> Locale.Language {
        switch language.code {
        case "zh-CN": Locale.Language(identifier: "zh-Hans")
        case "zh-TW", "zh-HK": Locale.Language(identifier: "zh-Hant")
        default: Locale.Language(identifier: language.code)
        }
    }
}

/// 請系統下載 Apple 翻譯所需的語言包（系統會顯示下載確認視窗）。
struct AppleLanguageDownloadView: View {
    let source: String
    let target: String
    var onFinish: () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var isPreparing = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("下載翻譯語言")
                .appFont(.title3, weight: .bold)
            Text("Apple 翻譯需要先下載這組語言才能在裝置上翻譯。下載後可離線使用。")
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(verbatim: "\(TranslationLanguage.named(source).name) → \(TranslationLanguage.named(target).name)")
                .appFont(.headline)
            Button {
                isPreparing = true
                configuration = TranslationSession.Configuration(
                    source: AppleTranslator.language(.named(source)),
                    target: AppleTranslator.language(.named(target))
                )
            } label: {
                if isPreparing { ProgressView() } else { Text("下載").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.glassProminent)
            .disabled(isPreparing)
        }
        .padding(28)
        .translationTask(configuration) { session in
            try? await session.prepareTranslation()
            onFinish()
        }
    }
}
