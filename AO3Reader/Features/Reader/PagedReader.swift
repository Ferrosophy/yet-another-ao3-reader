// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

/// 一章的排版內容（翻頁模式）。`signature` 改變時重新分頁。
struct PagedContent {
    struct Span {
        var paragraph: Paragraph
        var range: NSRange
    }

    var signature: Int
    var chapterIndex: Int
    var text: NSAttributedString
    var spans: [Span]
}

extension NSAttributedString.Key {
    /// 標記譯文範圍，翻頁模式繪製側條或卡片底色
    static let translationDecoration = NSAttributedString.Key("AO3TranslationDecoration")
}

final class TranslationDecoration: NSObject {
    let style: TranslationAppearance.Style
    let color: UIColor

    init(style: TranslationAppearance.Style, color: UIColor) {
        self.style = style
        self.color = color
    }
}

/// 翻頁模式中的作者註
struct PagedNote {
    var id: String
    var title: String
    var text: String
}

/// 把章節段落（含沉浸式譯文）組成 NSAttributedString，供 TextKit 分頁。
@MainActor
enum PagedTextBuilder {
    static func build(
        title: String?,
        summary: String?,
        chapterTitle: String?,
        chapterIndex: Int,
        chapter: Chapter,
        /// 章首與章末的作者註（標題、內容、譯文 ID）
        leadingNotes: [PagedNote] = [],
        trailingNotes: [PagedNote] = [],
        translations: [Paragraph.ID: ParagraphTranslation],
        showsTranslation: Bool,
        mode: BilingualDisplayMode,
        style: ReaderStyle,
        textColor: UIColor,
        secondaryColor: UIColor
    ) -> (NSAttributedString, [PagedContent.Span]) {
        let layout = style.layout
        let result = NSMutableAttributedString()
        var spans: [PagedContent.Span] = []

        func paragraphStyle(after spacing: Double, indent: CGFloat = 0, alignment: NSTextAlignment = .natural) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = layout.lineSpacing
            // TextKit 在段落最後一行之後也會加上行距，SwiftUI 不會；扣掉以與滾動模式的段距一致
            paragraph.paragraphSpacing = max(spacing - layout.lineSpacing, 0)
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent
            paragraph.alignment = alignment
            return paragraph
        }
        func append(_ string: String, font: UIFont, color: UIColor, paragraph: NSParagraphStyle,
                    decoration: TranslationDecoration? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: layout.letterSpacing,
            ]
            if let decoration { attributes[.translationDecoration] = decoration }
            result.append(NSAttributedString(string: string + "\n", attributes: attributes))
        }
        /// 譯文的側條 / 卡片底色，由 PageTextView 繪製（與捲動模式外觀一致）
        let decoration: TranslationDecoration? = switch style.translation.style {
        case .bar: TranslationDecoration(style: .bar, color: UIColor(style.accent).withAlphaComponent(0.6))
        case .card: TranslationDecoration(style: .card, color: textColor.withAlphaComponent(0.07))
        case .plain: nil
        }

        let translationColor = style.translation.followsTextColor == true
            ? textColor
            : style.translation.colorHex.flatMap(Color.init(hex:)).map(UIColor.init) ?? secondaryColor
        let smallFont = UIFont.preferredFont(forTextStyle: .footnote)
        let translationIndent: CGFloat = style.translation.style == .plain ? 0 : 12

        /// 標題與簡介的沉浸式譯文：已完成才排入（載入中不佔版面，避免分頁跳動）
        func appendMetaTranslation(_ id: String, scale: Double, weight: UIFont.Weight? = nil) {
            guard showsTranslation, case .done(let text) = translations[id] else { return }
            append(text,
                   font: style.uiFont(scale: scale * style.translation.scale, weight: weight, italic: style.translation.italic),
                   color: translationColor,
                   paragraph: paragraphStyle(after: layout.paragraphSpacing * 1.5, indent: translationIndent),
                   decoration: decoration)
        }

        if let title {
            append(title, font: style.uiFont(scale: 1.5, weight: .bold), color: textColor, paragraph: paragraphStyle(after: layout.paragraphSpacing * 1.5))
        }
        if let summary {
            append(summary, font: style.uiFont(), color: textColor, paragraph: paragraphStyle(after: layout.paragraphSpacing))
            if TranslationVisibility.readerSummary { appendMetaTranslation(ReaderViewModel.summaryID, scale: 1) }
        }
        if let chapterTitle {
            append(chapterTitle, font: style.uiFont(scale: 1.2, weight: .semibold), color: textColor, paragraph: paragraphStyle(after: layout.paragraphSpacing * 1.5))
            appendMetaTranslation(ReaderViewModel.chapterTitleID(chapterIndex), scale: 1.1, weight: .semibold)
        }
        func appendNote(_ note: PagedNote) {
            append(note.title, font: style.uiFont(scale: 0.8, weight: .semibold), color: secondaryColor,
                   paragraph: paragraphStyle(after: 4))
            // 作者註與正文使用相同字體
            append(note.text, font: style.uiFont(), color: textColor, paragraph: paragraphStyle(after: layout.paragraphSpacing))
            if TranslationVisibility.readerNotes { appendMetaTranslation(note.id, scale: 1) }
        }
        /// 作者註與正文之間的分隔線，避免分不清哪裡是註、哪裡是正文
        func appendDivider() {
            append("────────────", font: smallFont, color: secondaryColor.withAlphaComponent(0.5),
                   paragraph: paragraphStyle(after: layout.paragraphSpacing * 1.5, alignment: .center))
        }
        for note in leadingNotes { appendNote(note) }
        if !leadingNotes.isEmpty { appendDivider() }

        for paragraph in chapter.paragraphs {
            let start = result.length
            switch paragraph.kind {
            case .separator:
                append("＊　＊　＊", font: smallFont, color: secondaryColor, paragraph: paragraphStyle(after: layout.paragraphSpacing, alignment: .center))
            case .body, .heading:
                let state = showsTranslation ? translations[paragraph.id] : nil
                var doneText: String?
                if case .done(let text) = state { doneText = text }
                let showsOriginal = !(showsTranslation && mode == .translationOnly && doneText != nil)
                if showsOriginal {
                    let font = paragraph.kind == .heading ? style.uiFont(scale: 1.2, weight: .semibold) : style.uiFont()
                    let spacing = showsTranslation ? layout.lineSpacing + 4 : layout.paragraphSpacing
                    append(paragraph.text, font: font, color: textColor, paragraph: paragraphStyle(after: spacing))
                }
                if showsTranslation {
                    switch state {
                    case .done(let text):
                        if mode == .bilingual {
                            let indent = translationIndent
                            append(text,
                                   font: style.uiFont(scale: style.translation.scale, italic: style.translation.italic),
                                   color: translationColor,
                                   paragraph: paragraphStyle(after: layout.paragraphSpacing, indent: indent),
                                   decoration: decoration)
                        } else {
                            append(text, font: style.uiFont(), color: textColor, paragraph: paragraphStyle(after: layout.paragraphSpacing))
                        }
                    case .failed:
                        append("翻譯失敗，可在控制列重新翻譯本章", font: smallFont, color: .systemRed, paragraph: paragraphStyle(after: layout.paragraphSpacing))
                    case .loading, nil:
                        append("翻譯中…", font: smallFont, color: secondaryColor.withAlphaComponent(0.6), paragraph: paragraphStyle(after: layout.paragraphSpacing, indent: 12))
                    }
                }
            }
            spans.append(.init(paragraph: paragraph, range: NSRange(location: start, length: result.length - start)))
        }
        if !trailingNotes.isEmpty { appendDivider() }
        for note in trailingNotes { appendNote(note) }
        return (result, spans)
    }

    /// 以 TextKit 1 逐頁填滿文字容器，回傳每頁的字元範圍。
    static func paginate(_ text: NSAttributedString, size: CGSize) -> [NSRange] {
        guard size.width > 20, size.height > 20, text.length > 0 else { return [NSRange(location: 0, length: text.length)] }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        var ranges: [NSRange] = []
        while ranges.count < 10_000 {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            let glyphRange = manager.glyphRange(for: container)
            guard glyphRange.length > 0 else { break }
            ranges.append(manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
            if NSMaxRange(glyphRange) >= manager.numberOfGlyphs { break }
        }
        return ranges.isEmpty ? [NSRange(location: 0, length: text.length)] : ranges
    }
}

/// 翻頁模式的頁面邊距。上下邊距以裝置安全區域（瀏海 / 動態島、Home 指示條）為基準，
/// 不受導覽列顯示與否影響，因此叫出控制列時正文不會上下移動。
struct PageMargins: Equatable {
    var left: CGFloat
    var right: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    /// 控制列鎖定（常駐）時額外保留的空間
    var extraTop: CGFloat = 0
    var extraBottom: CGFloat = 0

    func insets(safeArea: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(top: safeArea.top + top + extraTop, left: left,
                     bottom: safeArea.bottom + bottom + extraBottom, right: right)
    }
}

/// 頁面底色：仿真與覆蓋需要不透明的頁面（翻起或移開時才不會透出下一頁）。
enum PageBackground: Equatable {
    case clear
    case color(UIColor)
    case image(UIImage, dim: CGFloat, dimColor: UIColor)
}

enum DeviceInsets {
    /// 視窗的安全區域（不含導覽列），用於固定的翻頁邊距
    @MainActor static var current: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
    }
}

/// SwiftUI 包裝：翻頁閱讀器。
struct PagedReaderView: UIViewControllerRepresentable {
    let content: PagedContent
    /// 作品第一頁：標題、作者、系列、標籤、簡介等正文以外的資訊，可上下捲動；nil 表示沒有
    let header: AnyView?
    /// 每章最後一頁：Kudos 與評論等章末內容；nil 表示沒有
    let footer: AnyView?
    let transition: PageTransition
    let margins: PageMargins
    let background: PageBackground
    /// 首次顯示或切換章節時要定位到的段落
    let anchorParagraphID: String?
    let startAtEnd: Bool
    var onPageChange: ([Paragraph]) -> Void
    var onCenterTap: () -> Void
    var onBoundary: (_ forward: Bool) -> Void

    func makeUIViewController(context: Context) -> PagerController {
        PagerController()
    }

    func updateUIViewController(_ controller: PagerController, context: Context) {
        controller.onPageChange = onPageChange
        controller.onCenterTap = onCenterTap
        controller.onBoundary = onBoundary
        controller.update(
            content: content,
            header: header,
            footer: footer,
            transition: transition,
            margins: margins,
            background: background,
            anchorParagraphID: anchorParagraphID,
            startAtEnd: startAtEnd
        )
    }
}

/// 單頁的共同基底：負責頁面底色（純色或背景圖）。
class ReaderPage: UIViewController {
    let index: Int
    private let pageBackground: PageBackground

    init(index: Int, background: PageBackground) {
        self.index = index
        self.pageBackground = background
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch pageBackground {
        case .clear:
            view.backgroundColor = .clear
        case .color(let color):
            view.backgroundColor = color
        case .image(let image, let dim, let dimColor):
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.frame = view.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let overlay = UIView(frame: view.bounds)
            overlay.backgroundColor = dimColor.withAlphaComponent(dim)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(imageView)
            view.addSubview(overlay)
        }
    }
}

/// 正文頁：以 TextKit 1 直接繪製，排版與分頁完全一致。
/// 不使用 UITextView：它是捲動視圖，安全區域改變（叫出控制列）時會自動調整內距而讓文字上下移動，
/// 且在仿真翻頁的截圖中可能還沒完成繪製而顯示空白。
final class TextPageController: ReaderPage {
    private let text: NSAttributedString
    private let insets: UIEdgeInsets

    init(index: Int, text: NSAttributedString, insets: UIEdgeInsets, background: PageBackground) {
        self.text = text
        self.insets = insets
        super.init(index: index, background: background)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let textView = PageTextView(text: text, insets: insets)
        textView.frame = view.bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(textView)
    }
}

final class PageTextView: UIView {
    private let text: NSAttributedString
    private let insets: UIEdgeInsets

    init(text: NSAttributedString, insets: UIEdgeInsets) {
        self.text = text
        self.insets = insets
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PageTextView, _) in view.setNeedsDisplay() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: bounds.width - insets.left - insets.right,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        let glyphs = manager.glyphRange(for: container)
        let origin = CGPoint(x: insets.left, y: insets.top)
        manager.drawBackground(forGlyphRange: glyphs, at: origin)
        drawDecorations(manager: manager, container: container, origin: origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }

    /// 譯文側條與卡片底色
    private func drawDecorations(manager: NSLayoutManager, container: NSTextContainer, origin: CGPoint) {
        text.enumerateAttribute(.translationDecoration, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let decoration = value as? TranslationDecoration else { return }
            let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var used = CGRect.null
            manager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineRange, _ in
                // 只有換行字元的空行不算
                if NSIntersectionRange(lineRange, glyphRange).length > 0, usedRect.width > 1 { used = used.union(usedRect) }
            }
            guard !used.isNull else { return }
            decoration.color.setFill()
            switch decoration.style {
            case .bar:
                UIBezierPath(roundedRect: CGRect(x: origin.x, y: origin.y + used.minY + 2, width: 3, height: max(used.height - 4, 4)),
                             cornerRadius: 1.5).fill()
            case .card:
                UIBezierPath(roundedRect: CGRect(x: origin.x, y: origin.y + used.minY - 4,
                                                 width: container.size.width, height: used.height + 8),
                             cornerRadius: 8).fill()
            case .plain:
                break
            }
        }
    }
}

/// 作品資訊頁（第一頁）：SwiftUI 內容，可上下捲動。
final class HeaderPageController: ReaderPage {
    let hosting: UIHostingController<AnyView>

    init(index: Int, rootView: AnyView, background: PageBackground) {
        hosting = UIHostingController(rootView: rootView)
        super.init(index: index, background: background)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 不讓安全區域影響版面，邊距由內容自行處理
        hosting.safeAreaRegions = []
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}

/// 翻頁控制器：仿真（UIPageViewController 捲頁，跟隨手指）、平滑（滑動）、
/// 覆蓋（平移的卡片：上層頁面整張水平移動，邊緣跟隨手指）、淡入淡出。
/// 點擊左側 / 右側三分之一翻頁，中間切換控制列；在章首 / 章末繼續翻頁時切換章節。
final class PagerController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
    UIGestureRecognizerDelegate {
    var onPageChange: (([Paragraph]) -> Void)?
    var onCenterTap: (() -> Void)?
    var onBoundary: ((Bool) -> Void)?

    private var content: PagedContent?
    private var header: AnyView?
    private var footer: AnyView?
    private var pageRanges: [NSRange] = []
    /// 目前頁碼（含資訊頁；有資訊頁時第 0 頁為資訊頁）
    private var currentIndex = 0
    private var transition: PageTransition = .curl
    private var margins = PageMargins(left: 20, right: 20, top: 20, bottom: 20)
    private var background: PageBackground = .clear
    private var laidOutSize: CGSize = .zero
    private var laidOutSignature: Int?
    private var laidOutInsets: UIEdgeInsets = .zero
    private var laidOutHeaderOffset = 0
    private var lastContent: PagedContent?
    private var pendingAnchor: String?
    private var pendingStartAtEnd = false

    private var pageViewController: UIPageViewController?
    private var currentPage: ReaderPage?
    private var isAnimating = false
    /// 翻頁動畫進行中收到新內容時，等動畫結束再重新排版（否則舊頁殘留造成文字重疊）
    private var needsRelayout = false
    /// 換章時的翻頁方向（nil 表示不需要動畫，例如第一次載入）
    private var pendingChapterDirection: Bool?
    private let headerHosts = NSHashTable<UIHostingController<AnyView>>.weakObjects()
    private let footerHosts = NSHashTable<UIHostingController<AnyView>>.weakObjects()

    private var headerOffset: Int { header == nil ? 0 : 1 }
    private var footerCount: Int { footer == nil ? 0 : 1 }
    /// 章末頁的頁碼（在所有正文頁之後）
    private var footerIndex: Int { headerOffset + pageRanges.count }
    private var pageCount: Int { headerOffset + pageRanges.count + footerCount }
    private var insets: UIEdgeInsets { margins.insets(safeArea: view.window?.safeAreaInsets ?? DeviceInsets.current) }

    private var visiblePage: ReaderPage? {
        (pageViewController?.viewControllers?.first as? ReaderPage) ?? currentPage
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.size != laidOutSize || insets != laidOutInsets { relayout() }
    }

    func update(content: PagedContent, header: AnyView?, footer: AnyView?, transition: PageTransition, margins: PageMargins,
                background: PageBackground, anchorParagraphID: String?, startAtEnd: Bool) {
        let chapterChanged = self.content?.chapterIndex != content.chapterIndex
        let headerChanged = (header == nil) != (self.header == nil) || (footer == nil) != (self.footer == nil)
        let transitionChanged = transition != self.transition
        let backgroundChanged = background != self.background
        if chapterChanged {
            pendingAnchor = startAtEnd ? nil : anchorParagraphID
            pendingStartAtEnd = startAtEnd
            // 換章與章內翻頁使用同樣的翻頁動畫
            if let old = self.content?.chapterIndex, transition == self.transition { pendingChapterDirection = content.chapterIndex > old }
        }
        // 停在第一章的作品資訊頁時從目錄再選第一章：跳到第一個正文頁
        var jumpToText = false
        if !chapterChanged, let anchor = anchorParagraphID, anchor.hasPrefix("chaptertext-"), currentIndex < headerOffset {
            pendingAnchor = anchor
            jumpToText = true
        }
        self.content = content
        self.header = header
        self.footer = footer
        self.transition = transition
        self.margins = margins
        self.background = background
        if let header {
            for host in headerHosts.allObjects { host.rootView = header }
        }
        if let footer {
            for host in footerHosts.allObjects { host.rootView = footer }
        }
        if transitionChanged { rebuildContainer() }
        if chapterChanged || headerChanged || content.signature != laidOutSignature || insets != laidOutInsets
            || transitionChanged || backgroundChanged || jumpToText {
            relayout()
        }
    }

    // MARK: Layout

    private func relayout() {
        guard let content, view.bounds.width > 0, view.bounds.height > 0 else { return }
        if isAnimating || card != nil {
            needsRelayout = true
            return
        }
        let insets = insets
        // 先記住目前頁首在哪個段落的第幾個字，重新分頁後回到同一位置
        var anchor: (id: String, offset: Int)?
        var onHeader = false
        // 停在章末頁時，重新分頁後仍停在章末頁（譯文載入會改變正文頁數）
        let onFooter = footer != nil && pendingAnchor == nil && laidOutSignature != nil && lastContent?.chapterIndex == content.chapterIndex
            && currentIndex - laidOutHeaderOffset >= pageRanges.count
        if let pending = pendingAnchor {
            anchor = (pending, 0)
        } else if laidOutSignature != nil, let old = lastContent, old.chapterIndex == content.chapterIndex {
            let oldText = currentIndex - laidOutHeaderOffset
            if oldText < 0 {
                onHeader = true
            } else if pageRanges.indices.contains(oldText) {
                let location = pageRanges[oldText].location
                if let span = old.spans.first(where: { NSLocationInRange(location, $0.range) }) {
                    anchor = (span.paragraph.id, location - span.range.location)
                }
            }
        }

        let size = CGSize(width: view.bounds.width - insets.left - insets.right,
                          height: view.bounds.height - insets.top - insets.bottom - 2)
        pageRanges = PagedTextBuilder.paginate(content.text, size: size)

        if pendingStartAtEnd {
            currentIndex = pageCount - 1
        } else if let anchor, anchor.id.hasPrefix("chaptertext-") {
            // 目錄選第一章：跳過作品資訊頁，從第一個正文頁開始
            currentIndex = headerOffset
        } else if onHeader {
            currentIndex = 0
        } else if onFooter {
            currentIndex = pageCount - 1
        } else if let anchor, let span = content.spans.first(where: { $0.paragraph.id == anchor.id }) {
            let target = span.range.location + min(anchor.offset, max(span.range.length - 1, 0))
            currentIndex = headerOffset + (pageRanges.firstIndex { NSLocationInRange(target, $0) } ?? 0)
        } else if lastContent?.chapterIndex != content.chapterIndex {
            currentIndex = 0
        }
        currentIndex = min(max(currentIndex, 0), max(pageCount - 1, 0))
        pendingAnchor = nil
        pendingStartAtEnd = false

        laidOutSize = view.bounds.size
        laidOutSignature = content.signature
        laidOutInsets = insets
        laidOutHeaderOffset = headerOffset
        lastContent = content
        if pageViewController == nil && currentPage == nil { rebuildContainer() }
        let direction = pendingChapterDirection
        pendingChapterDirection = nil
        show(index: currentIndex, animated: direction != nil, forward: direction ?? true)
    }

    /// 動畫結束後處理期間延後的重新排版
    private func animationDidEnd() {
        isAnimating = false
        if needsRelayout {
            needsRelayout = false
            relayout()
        }
    }

    /// 仿真與覆蓋的頁面必須不透明；平滑與淡入淡出直接透出閱讀背景
    private var pageBackground: PageBackground {
        transition == .curl || transition == .cover ? background : .clear
    }

    private func makePage(_ index: Int) -> ReaderPage? {
        if let header, index == 0 {
            let page = HeaderPageController(index: 0, rootView: header, background: pageBackground)
            headerHosts.add(page.hosting)
            return page
        }
        if let footer, index == footerIndex {
            let page = HeaderPageController(index: index, rootView: footer, background: pageBackground)
            footerHosts.add(page.hosting)
            return page
        }
        let textIndex = index - headerOffset
        guard let content, pageRanges.indices.contains(textIndex) else { return nil }
        let text = content.text.attributedSubstring(from: pageRanges[textIndex])
        return TextPageController(index: index, text: text, insets: insets, background: pageBackground)
    }

    private func rebuildContainer() {
        pageViewController?.willMove(toParent: nil)
        pageViewController?.view.removeFromSuperview()
        pageViewController?.removeFromParent()
        pageViewController = nil
        currentPage?.view.removeFromSuperview()
        currentPage?.removeFromParent()
        currentPage = nil

        switch transition {
        case .curl, .slide:
            var options: [UIPageViewController.OptionsKey: Any] = [:]
            if transition == .curl {
                options[.spineLocation] = NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)
            }
            let controller = UIPageViewController(
                transitionStyle: transition == .curl ? .pageCurl : .scroll,
                navigationOrientation: .horizontal,
                options: options
            )
            controller.dataSource = self
            controller.delegate = self
            // 單面翻頁：翻起的頁面背面由系統以頁面本身（與閱讀背景同色，跟隨淺色 / 深色模式）繪製
            controller.isDoubleSided = false
            addChild(controller)
            controller.view.frame = view.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.view.backgroundColor = .clear
            view.insertSubview(controller.view, at: 0)
            controller.didMove(toParent: self)
            // 由本控制器統一處理點擊翻頁
            for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
                recognizer.isEnabled = false
            }
            // 平滑模式內部的捲動視圖不隨安全區域調整內距
            for case let scrollView as UIScrollView in controller.view.subviews {
                scrollView.contentInsetAdjustmentBehavior = .never
            }
            pageViewController = controller
        case .cover, .fade:
            break
        }
    }

    private func show(index: Int, animated: Bool, forward: Bool) {
        guard let page = makePage(index) else { return }
        if let pageViewController {
            currentIndex = index
            if animated {
                // 動畫中不得再次 setViewControllers（UIPageViewController 會丟出例外而閃退）
                isAnimating = true
                pageViewController.setViewControllers([page], direction: forward ? .forward : .reverse, animated: true) { [weak self] _ in
                    self?.animationDidEnd()
                }
            } else {
                pageViewController.setViewControllers([page], direction: .forward, animated: false)
            }
            notifyPageChange()
        } else if animated, currentPage != nil {
            transitionTo(page, forward: forward)
            return
        } else {
            // 移除所有舊頁（包含動畫中途留下的），避免文字重疊
            for child in children where child is ReaderPage {
                child.willMove(toParent: nil)
                child.view.removeFromSuperview()
                child.removeFromParent()
            }
            install(page, below: nil)
            currentPage = page
            currentIndex = index
            notifyPageChange()
        }
    }

    private func install(_ page: ReaderPage, below other: UIView?, above: UIView? = nil) {
        addChild(page)
        page.view.frame = view.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let other {
            view.insertSubview(page.view, belowSubview: other)
        } else if let above {
            view.insertSubview(page.view, aboveSubview: above)
        } else {
            view.insertSubview(page.view, at: 0)
        }
        page.didMove(toParent: self)
    }

    // MARK: 覆蓋（卡牌）與淡入淡出

    /// 進行中的卡牌切換；`target` 為 nil 表示已到章首 / 章末
    private struct CardTransition {
        let forward: Bool
        let current: ReaderPage
        let target: ReaderPage?
    }

    private var card: CardTransition?

    private func beginCard(forward: Bool, target explicitTarget: ReaderPage? = nil) -> CardTransition? {
        guard let current = currentPage else { return nil }
        let target = explicitTarget ?? makePage(currentIndex + (forward ? 1 : -1))
        if let target {
            if forward {
                // 前進：目前頁像卡牌一樣被拖走，露出下面的下一頁
                install(target, below: current.view)
            } else {
                // 後退：上一頁從左側像卡牌一樣蓋回來
                install(target, below: nil, above: current.view)
            }
            let moving = forward ? current.view! : target.view!
            moving.layer.shadowColor = UIColor.black.cgColor
            moving.layer.shadowOpacity = 0.3
            moving.layer.shadowRadius = 12
            moving.layer.shadowOffset = CGSize(width: 4, height: 0)
            moving.layer.shadowPath = UIBezierPath(rect: view.bounds).cgPath
        }
        let transition = CardTransition(forward: forward, current: current, target: target)
        card = transition
        applyCard(transition, progress: 0)
        return transition
    }

    /// progress：0 = 未翻，1 = 翻完
    private func applyCard(_ card: CardTransition, progress: CGFloat) {
        let width = view.bounds.width
        let p = min(max(progress, 0), 1)
        guard let target = card.target else {
            // 章首 / 章末：只做阻尼位移提示
            let offset = (card.forward ? -1 : 1) * min(p * width, 60)
            card.current.view.transform = CGAffineTransform(translationX: offset * 0.5, y: 0)
            return
        }
        // 平移的卡片：上層頁面整張水平移動，邊緣與手指位置同步；下層頁面保持不動
        if card.forward {
            card.current.view.transform = CGAffineTransform(translationX: -width * p, y: 0)
            target.view.transform = .identity
        } else {
            target.view.transform = CGAffineTransform(translationX: -width * (1 - p), y: 0)
            card.current.view.transform = .identity
        }
    }

    private func finishCard(_ card: CardTransition, complete: Bool, velocity: CGFloat = 0) {
        isAnimating = true
        let animations = { self.applyCard(card, progress: complete ? 1 : 0) }
        let completion: (Bool) -> Void = { _ in
            card.current.view.transform = .identity
            card.target?.view.transform = .identity
            card.current.view.layer.shadowOpacity = 0
            card.target?.view.layer.shadowOpacity = 0
            if complete, let target = card.target {
                card.current.willMove(toParent: nil)
                card.current.view.removeFromSuperview()
                card.current.removeFromParent()
                self.currentPage = target
                self.currentIndex = target.index
                self.notifyPageChange()
            } else if let target = card.target {
                target.willMove(toParent: nil)
                target.view.removeFromSuperview()
                target.removeFromParent()
            }
            self.card = nil
            self.animationDidEnd()
        }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9,
                       initialSpringVelocity: min(abs(velocity) / max(view.bounds.width, 1), 4),
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: animations, completion: completion)
    }

    private func transitionTo(_ page: ReaderPage, forward: Bool) {
        guard let current = currentPage else { return }
        if transition == .fade {
            isAnimating = true
            install(page, below: nil, above: current.view)
            page.view.alpha = 0
            UIView.animate(withDuration: 0.3, animations: {
                page.view.alpha = 1
                current.view.alpha = 0
            }, completion: { _ in
                current.willMove(toParent: nil)
                current.view.removeFromSuperview()
                current.removeFromParent()
                current.view.alpha = 1
                self.currentPage = page
                self.currentIndex = page.index
                self.notifyPageChange()
                self.animationDidEnd()
            })
        } else {
            // 點擊翻頁與換章：以同一套卡牌動畫自動完成
            if let card = beginCard(forward: forward, target: page) { finishCard(card, complete: card.target != nil) }
        }
    }

    private func notifyPageChange() {
        guard let content else { return }
        // 章末頁視為最後一個正文頁（閱讀進度為本章結尾）
        let textIndex = min(currentIndex - headerOffset, pageRanges.count - 1)
        var paragraphs: [Paragraph] = []
        if pageRanges.indices.contains(textIndex) {
            let range = pageRanges[textIndex]
            paragraphs = content.spans
                .filter { NSIntersectionRange($0.range, range).length > 0 }
                .map(\.paragraph)
        }
        // 避免在 SwiftUI 更新期間修改狀態
        DispatchQueue.main.async { [weak self] in self?.onPageChange?(paragraphs) }
    }

    // MARK: Navigation

    private func turn(forward: Bool) {
        guard !isAnimating else { return }
        let target = currentIndex + (forward ? 1 : -1)
        guard (0..<pageCount).contains(target) else {
            onBoundary?(forward)
            return
        }
        show(index: target, animated: true, forward: forward)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let x = recognizer.location(in: view).x
        let width = view.bounds.width
        if x < width * 0.3 { turn(forward: false) }
        else if x > width * 0.7 { turn(forward: true) }
        else { onCenterTap?() }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view).x
        let velocity = recognizer.velocity(in: view).x
        let width = max(view.bounds.width, 1)

        // 仿真 / 平滑由 UIPageViewController 跟隨手指；這裡只處理章首 / 章末的換章
        if pageViewController != nil {
            guard recognizer.state == .ended else { return }
            if translation < -60, currentIndex >= pageCount - 1 { onBoundary?(true) }
            if translation > 60, currentIndex <= 0 { onBoundary?(false) }
            return
        }

        switch recognizer.state {
        case .began:
            guard !isAnimating, card == nil else { return }
            if transition == .cover {
                _ = beginCard(forward: velocity < 0 || (velocity == 0 && translation < 0))
            }
        case .changed:
            guard let card else { return }
            let progress = (card.forward ? -translation : translation) / width
            applyCard(card, progress: progress)
        case .ended, .cancelled, .failed:
            if let card {
                let progress = (card.forward ? -translation : translation) / width
                let flick = card.forward ? velocity < -400 : velocity > 400
                let complete = recognizer.state == .ended && (progress > 0.3 || (flick && progress > 0.05))
                if card.target == nil {
                    finishCard(card, complete: false)
                    if complete || progress > 0.15 { onBoundary?(card.forward) }
                } else {
                    finishCard(card, complete: complete, velocity: velocity)
                }
            } else if transition == .fade, recognizer.state == .ended, abs(translation) > 40 {
                turn(forward: translation < 0)
            }
        default:
            break
        }
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        // 只接手水平拖動；資訊頁的上下捲動交給捲動視圖
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 資訊頁上的點擊交給頁內的按鈕與連結
        if gestureRecognizer is UITapGestureRecognizer, visiblePage is HeaderPageController { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // 與 UIPageViewController 的拖動並存，用於章首 / 章末換章
        pageViewController != nil && gestureRecognizer is UIPanGestureRecognizer
    }

    // MARK: UIPageViewController

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ReaderPage else { return nil }
        return makePage(page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ReaderPage else { return nil }
        return makePage(page.index + 1)
    }

    /// 手勢翻頁開始：期間收到的新內容延後到翻頁結束再排版
    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        isAnimating = true
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        defer { animationDidEnd() }
        guard completed, let page = pageViewController.viewControllers?.first as? ReaderPage else { return }
        currentIndex = page.index
        notifyPageChange()
    }
}
