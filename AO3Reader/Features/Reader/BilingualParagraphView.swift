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
    /// 譯文側條等強調色（明確傳入，避免在部分容器中取不到 tint 而不顯示）
    var accent: Color = .accentColor

    // MARK: SwiftUI

    /// 滾動模式直接使用與翻頁模式相同的 UIFont，確保兩種模式在同一排版數值下字形、字重完全一致
    func font(scale: Double = 1, weight: UIFont.Weight? = nil, italic: Bool = false) -> Font {
        Font(uiFont(scale: scale, weight: weight, italic: italic))
    }

    /// 使用者匯入的字體（SwiftUI Text 套用時會退回系統字體，改由 UIKit 繪製）
    var usesImportedFont: Bool { font.hasPrefix("custom:") }

    var bodyFont: Font { font() }
    var headingFont: Font { font(scale: 1.2, weight: .semibold) }
    var titleFont: Font { font(scale: 1.5, weight: .bold) }
    var translationFont: Font { font(scale: translation.scale, italic: translation.italic) }

    /// nil 為次要文字色；跟隨正文時使用正文顏色
    var translationColor: Color? {
        if translation.followsTextColor == true { return textColor ?? .primary }
        return translation.colorHex.flatMap(Color.init(hex:))
    }

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
            // 與翻頁模式相同的字型、顏色與間距
            Text("＊　＊　＊")
                .font(.footnote)
                .foregroundStyle(style.textColor.map { AnyShapeStyle($0.opacity(0.65)) } ?? AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity)
        case .body, .heading:
            VStack(alignment: .leading, spacing: style.layout.lineSpacing + 4) {
                if showsOriginal {
                    ReaderTextView(text: paragraph.text,
                                   font: paragraph.kind == .heading ? style.uiFont(scale: 1.2, weight: .semibold) : style.uiFont(),
                                   style: style)
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
        if mode == .translationOnly, case .done(let text) = translation {
            ReaderTextView(text: text, font: style.uiFont(), style: style)
        } else {
            ImmersiveTranslationView(translation: translation, style: style, onRetry: onRetry)
        }
    }
}

/// 沉浸式譯文區塊（正文段落、章節標題、簡介共用）：顯示在原文下方，依「譯文外觀」設定呈現；
/// 載入中與失敗時顯示狀態列。
struct ImmersiveTranslationView: View {
    let translation: ParagraphTranslation?
    let style: ReaderStyle
    /// 指定時取代譯文字型（例如章節標題使用較大的字）
    var font: UIFont?
    var onRetry: () -> Void

    var body: some View {
        switch translation {
        case .done(let text):
            styledTranslation(text)
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
        let colored = ReaderTextView(
            text: text,
            font: font ?? style.uiFont(scale: style.translation.scale, italic: style.translation.italic),
            style: style,
            color: style.translationColor,
            secondary: style.translationColor == nil
        )
        switch style.translation.style {
        case .bar:
            colored
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(style.accent.opacity(0.6))
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

/// 閱讀頁的文字。系統與內建字族用 SwiftUI Text（保留文字選取）；
/// 匯入的字體在 SwiftUI Text 中會退回系統字體，改用與翻頁模式相同的 UIKit 繪製，確保字體生效。
struct ReaderTextView: View {
    let text: String
    let font: UIFont
    let style: ReaderStyle
    /// nil 時沿用上層文字顏色（正文）或次要文字色（`secondary`）
    var color: Color?
    var secondary = false

    var body: some View {
        if style.usesImportedFont {
            ReaderLabel(text: text, font: font, color: labelColor,
                        lineSpacing: style.layout.lineSpacing, kern: style.layout.letterSpacing)
        } else if let color {
            styledText.foregroundStyle(color)
        } else if secondary {
            styledText.foregroundStyle(.secondary)
        } else {
            styledText
        }
    }

    private var styledText: Text {
        Text(text)
            .font(Font(font))
            .tracking(style.layout.letterSpacing)
            .lineSpacing(style.layout.lineSpacing)
    }

    private var labelColor: UIColor {
        if let color { return UIColor(color) }
        let base = style.textColor.map(UIColor.init) ?? .label
        return secondary ? base.withAlphaComponent(0.6) : base
    }
}

/// 以 UILabel 繪製的多行文字，高度依寬度自動計算。
struct ReaderLabel: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    let lineSpacing: CGFloat
    let kern: CGFloat

    private var attributed: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern,
        ])
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.isUserInteractionEnabled = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return CGSize(width: width, height: ceil(bounds.height))
    }
}
