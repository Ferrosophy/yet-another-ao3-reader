import SwiftUI

struct ReaderStyle {
    var fontSize: Double
    var lineSpacing: Double
    /// "system" / "serif" / "rounded" / "custom:<PostScript 名稱>"
    var font: String

    private func makeFont(size: Double, weight: Font.Weight = .regular) -> Font {
        if font.hasPrefix("custom:") {
            return .custom(String(font.dropFirst("custom:".count)), size: size).weight(weight)
        }
        let design: Font.Design = switch font {
        case "serif": .serif
        case "rounded": .rounded
        default: .default
        }
        return .system(size: size, weight: weight, design: design)
    }

    var bodyFont: Font { makeFont(size: fontSize) }
    var headingFont: Font { makeFont(size: fontSize * 1.2, weight: .semibold) }
    var titleFont: Font { makeFont(size: fontSize * 1.5, weight: .bold) }
    /// 譯文使用同一字體、略小字級，與原文區分但不突兀
    var translationFont: Font { makeFont(size: fontSize * 0.95) }
}

/// 沉浸式雙語段落：原文在上，譯文緊接其下並以強調色側條標示，不取代原文。
struct BilingualParagraphView: View {
    let paragraph: Paragraph
    let translation: ParagraphTranslation?
    let showsTranslation: Bool
    let mode: BilingualDisplayMode
    let style: ReaderStyle
    var onRetry: () -> Void

    var body: some View {
        switch paragraph.kind {
        case .separator:
            Text("＊　＊　＊")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .body, .heading:
            VStack(alignment: .leading, spacing: style.lineSpacing + 4) {
                if showsOriginal {
                    Text(paragraph.text)
                        .font(paragraph.kind == .heading ? style.headingFont : style.bodyFont)
                        .lineSpacing(style.lineSpacing)
                }
                if showsTranslation {
                    translationView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    /// 「僅譯文」模式下，譯文完成後才隱藏原文；載入中或失敗時仍顯示原文。
    private var showsOriginal: Bool {
        guard showsTranslation, mode == .translationOnly, case .some(.done) = translation else { return true }
        return false
    }

    @ViewBuilder
    private var translationView: some View {
        switch translation {
        case .done(let text):
            if mode == .bilingual {
                Text(text)
                    .font(style.translationFont)
                    .lineSpacing(style.lineSpacing)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.tint.opacity(0.55))
                            .frame(width: 3)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(text)
                    .font(style.bodyFont)
                    .lineSpacing(style.lineSpacing)
            }
        case .failed(let message):
            Button(action: onRetry) {
                Label("翻譯失敗：\(message)　點擊重試", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .lineLimit(2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        case .loading, nil:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("翻譯中…")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.leading, 12)
        }
    }
}
