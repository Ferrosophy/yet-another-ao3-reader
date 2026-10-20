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

/// 請系統下載 Apple 翻譯所需的語言包（系統會顯示下載確認視窗），並顯示下載狀態。
///
/// Translation 框架沒有提供下載百分比，所以這裡每秒查詢一次語言包狀態，
/// 顯示「等待確認 → 下載中（已經過時間）→ 完成」；詳細進度可在系統設定的「翻譯」中查看。
struct AppleLanguageDownloadView: View {
    let source: String
    let target: String
    var onFinish: () -> Void

    private enum Phase: Equatable {
        case idle, downloading(Date), done, failed(String)
    }

    @State private var configuration: TranslationSession.Configuration?
    @State private var phase: Phase = .idle

    private var from: Locale.Language { AppleTranslator.language(.named(source)) }
    private var to: Locale.Language { AppleTranslator.language(.named(target)) }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: phase == .done ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(phase == .done ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
            Text("下載翻譯語言")
                .appFont(.title3, weight: .bold)
            Text(verbatim: "\(TranslationLanguage.named(source).name) → \(TranslationLanguage.named(target).name)")
                .appFont(.headline)
            status
            if phase == .idle {
                Button {
                    phase = .downloading(Date())
                    configuration = TranslationSession.Configuration(source: from, target: to)
                } label: {
                    Text("下載").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(28)
        .translationTask(configuration) { @Sendable session in
            do {
                try await session.prepareTranslation()
            } catch {
                let message = error.localizedDescription
                await MainActor.run { phase = .failed(message) }
            }
        }
        // 每秒查詢語言包是否已安裝
        .task(id: phase == .idle) {
            guard phase != .idle else { return }
            while !Task.isCancelled, case .downloading = phase {
                if await LanguageAvailability().status(from: from, to: to) == .installed {
                    phase = .done
                    try? await Task.sleep(for: .seconds(1))
                    onFinish()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .idle:
            Text("Apple 翻譯需要先下載這組語言才能在裝置上翻譯。下載後可離線使用。")
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .downloading(let start):
            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.linear)
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(start))
                    Text("下載中… 已經過 \(seconds) 秒")
                        .appFont(.callout)
                        .monospacedDigit()
                }
                Text("請在系統視窗中確認下載。下載期間可以離開這個畫面，完成後會自動開始翻譯；詳細進度可到「設定 › App › 翻譯 › 已下載的語言」查看。")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .done:
            Text("下載完成").appFont(.callout).foregroundStyle(.green)
        case .failed(let message):
            VStack(spacing: 10) {
                Text("下載未完成：\(message)")
                    .appFont(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("重試") {
                    configuration = nil
                    phase = .idle
                }
                .buttonStyle(.glass)
            }
        }
    }
}
