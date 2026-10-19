import SwiftUI
import UIKit

/// 閱讀排版：由外觀設定組合而成，捲動模式（SwiftUI）與翻頁模式（UIKit 排版）共用。
struct ReaderStyle {
    var layout: ReaderLayout
    /// "system" / "serif" / "rounded" / "family:<字族>" / "custom:<PostScript 名稱>"
    var font: String
    /// nil 為系統主要文字色
    var textColor: Color?
    var translation: TranslationAppearance

    // MARK: SwiftUI

    func font(scale: Double = 1, weight: Font.Weight? = nil) -> Font {
        let size = layout.fontSize * scale
        let weight = weight ?? layout.fontWeight.font
        if font.hasPrefix("custom:") {
            return .custom(String(font.dropFirst("custom:".count)), size: size).weight(weight)
        }
        if font.hasPrefix("family:") {
            return .custom(String(font.dropFirst("family:".count)), size: size).weight(weight)
        }
        let design: Font.Design = switch font {
        case "serif": .serif
        case "rounded": .rounded
        default: .default
        }
        return .system(size: size, weight: weight, design: design)
    }

    var bodyFont: Font { font() }
    var headingFont: Font { font(scale: 1.2, weight: .semibold) }
    var titleFont: Font { font(scale: 1.5, weight: .bold) }
    var translationFont: Font { font(scale: translation.fontScale) }

    var translationColor: Color? { translation.colorHex.flatMap(Color.init(hex:)) }

    // MARK: UIKit（翻頁模式排版）

    func uiFont(scale: Double = 1, weight: UIFont.Weight? = nil, italic: Bool = false) -> UIFont {
        let size = layout.fontSize * scale
        let weight = weight ?? layout.fontWeight.uiFont
        var result: UIFont
        if font.hasPrefix("custom:") {
            result = UIFont(name: String(font.dropFirst("custom:".count)), size: size) ?? .systemFont(ofSize: size, weight: weight)
        } else if font.hasPrefix("family:") {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: String(font.dropFirst("family:".count)),
                .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue],
            ])
            result = UIFont(descriptor: descriptor, size: size)
        } else {
            result = .systemFont(ofSize: size, weight: weight)
            let design: UIFontDescriptor.SystemDesign? = switch font {
            case "serif": .serif
            case "rounded": .rounded
            default: nil
            }
            if let design, let descriptor = result.fontDescriptor.withDesign(design) {
                result = UIFont(descriptor: descriptor, size: size)
            }
        }
        if italic, let descriptor = result.fontDescriptor.withSymbolicTraits(result.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            result = UIFont(descriptor: descriptor, size: size)
        }
        return result
    }
}

/// 沉浸式雙語段落：原文在上，譯文緊接其下，不取代原文。譯文外觀可在閱讀設定中自訂。
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
            VStack(alignment: .leading, spacing: style.layout.lineSpacing + 4) {
                if showsOriginal {
                    Text(paragraph.text)
                        .font(paragraph.kind == .heading ? style.headingFont : style.bodyFont)
                        .tracking(style.layout.letterSpacing)
                        .lineSpacing(style.layout.lineSpacing)
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
                styledTranslation(text)
            } else {
                Text(text)
                    .font(style.bodyFont)
                    .tracking(style.layout.letterSpacing)
                    .lineSpacing(style.layout.lineSpacing)
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

    @ViewBuilder
    private func styledTranslation(_ text: String) -> some View {
        let base = Text(text)
            .font(style.translationFont)
            .italic(style.translation.italic)
            .tracking(style.layout.letterSpacing)
            .lineSpacing(style.layout.lineSpacing)
        let colored = Group {
            if let color = style.translationColor {
                base.foregroundStyle(color)
            } else {
                base.foregroundStyle(.secondary)
            }
        }
        switch style.translation.style {
        case .bar:
            colored
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint.opacity(0.55))
                        .frame(width: 3)
                }
        case .card:
            colored
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 10))
        case .plain:
            colored
        }
    }
}
