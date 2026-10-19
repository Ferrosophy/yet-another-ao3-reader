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

/// 把章節段落（含沉浸式譯文）組成 NSAttributedString，供 TextKit 分頁。
@MainActor
enum PagedTextBuilder {
    static func build(
        title: String?,
        chapterTitle: String?,
        chapter: Chapter,
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
            paragraph.paragraphSpacing = spacing
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent
            paragraph.alignment = alignment
            return paragraph
        }
        func append(_ string: String, font: UIFont, color: UIColor, paragraph: NSParagraphStyle) {
            result.append(NSAttributedString(string: string + "\n", attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: layout.letterSpacing,
            ]))
        }

        if let title {
            append(title, font: style.uiFont(scale: 1.5, weight: .bold), color: textColor, paragraph: paragraphStyle(after: layout.paragraphSpacing * 1.5))
        }
        if let chapterTitle {
            append(chapterTitle, font: style.uiFont(scale: 1.2, weight: .semibold), color: textColor, paragraph: paragraphStyle(after: layout.paragraphSpacing * 1.5))
        }

        let translationColor = style.translation.colorHex.flatMap(Color.init(hex:)).map(UIColor.init) ?? secondaryColor
        let smallFont = UIFont.preferredFont(forTextStyle: .footnote)

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
                            let indent: CGFloat = style.translation.style == .plain ? 0 : 12
                            append(text,
                                   font: style.uiFont(scale: style.translation.fontScale, italic: style.translation.italic),
                                   color: translationColor,
                                   paragraph: paragraphStyle(after: layout.paragraphSpacing, indent: indent))
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

/// SwiftUI 包裝：翻頁閱讀器。
struct PagedReaderView: UIViewControllerRepresentable {
    let content: PagedContent
    let transition: PageTransition
    let insets: UIEdgeInsets
    let pageColor: UIColor
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
            transition: transition,
            insets: insets,
            pageColor: pageColor,
            anchorParagraphID: anchorParagraphID,
            startAtEnd: startAtEnd
        )
    }
}

/// 單頁：不可捲動、不可編輯的 TextKit 1 文字視圖，排版與分頁時一致。
final class PageContentController: UIViewController {
    let index: Int
    private let text: NSAttributedString
    private let insets: UIEdgeInsets
    private let pageColor: UIColor

    init(index: Int, text: NSAttributedString, insets: UIEdgeInsets, pageColor: UIColor) {
        self.index = index
        self.text = text
        self.insets = insets
        self.pageColor = pageColor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pageColor
        let textView = UITextView(usingTextLayoutManager: false)
        textView.attributedText = text
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = insets
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

/// 翻頁控制器：仿真（UIPageViewController 捲頁）、平滑（滑動）、覆蓋、淡入淡出。
/// 點擊左側 / 右側三分之一翻頁，中間切換控制列；在章首 / 章末繼續翻頁時切換章節。
final class PagerController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var onPageChange: (([Paragraph]) -> Void)?
    var onCenterTap: (() -> Void)?
    var onBoundary: ((Bool) -> Void)?

    private var content: PagedContent?
    private var pageRanges: [NSRange] = []
    private var currentIndex = 0
    private var transition: PageTransition = .curl
    private var insets: UIEdgeInsets = .zero
    private var pageColor: UIColor = .systemBackground
    private var laidOutSize: CGSize = .zero
    private var laidOutSignature: Int?
    private var laidOutInsets: UIEdgeInsets = .zero
    private var pendingAnchor: String?
    private var pendingStartAtEnd = false

    private var pageViewController: UIPageViewController?
    private var currentPage: PageContentController?
    private var isAnimating = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.size != laidOutSize { relayout() }
    }

    func update(content: PagedContent, transition: PageTransition, insets: UIEdgeInsets, pageColor: UIColor,
                anchorParagraphID: String?, startAtEnd: Bool) {
        let chapterChanged = self.content?.chapterIndex != content.chapterIndex
        let transitionChanged = transition != self.transition
        let colorChanged = pageColor != self.pageColor
        if chapterChanged {
            pendingAnchor = startAtEnd ? nil : anchorParagraphID
            pendingStartAtEnd = startAtEnd
        }
        self.content = content
        self.transition = transition
        self.insets = insets
        self.pageColor = pageColor
        if transitionChanged { rebuildContainer() }
        if chapterChanged || content.signature != laidOutSignature || insets != laidOutInsets || transitionChanged || colorChanged {
            relayout()
        }
    }

    // MARK: Layout

    private func relayout() {
        guard let content, view.bounds.width > 0, view.bounds.height > 0 else { return }
        // 先記住目前頁首在哪個段落的第幾個字，重新分頁後回到同一位置
        var anchor: (id: String, offset: Int)?
        if let pending = pendingAnchor {
            anchor = (pending, 0)
        } else if laidOutSignature != nil, pageRanges.indices.contains(currentIndex), let old = lastContent {
            let location = pageRanges[currentIndex].location
            if let span = old.spans.first(where: { NSLocationInRange(location, $0.range) }) {
                anchor = (span.paragraph.id, location - span.range.location)
            }
        }

        let size = CGSize(width: view.bounds.width - insets.left - insets.right,
                          height: view.bounds.height - insets.top - insets.bottom - 2)
        pageRanges = PagedTextBuilder.paginate(content.text, size: size)

        if pendingStartAtEnd {
            currentIndex = pageRanges.count - 1
        } else if let anchor, let span = content.spans.first(where: { $0.paragraph.id == anchor.id }) {
            let target = span.range.location + min(anchor.offset, max(span.range.length - 1, 0))
            currentIndex = pageRanges.firstIndex { NSLocationInRange(target, $0) } ?? 0
        } else if lastContent?.chapterIndex != content.chapterIndex {
            currentIndex = 0
        }
        currentIndex = min(max(currentIndex, 0), pageRanges.count - 1)
        pendingAnchor = nil
        pendingStartAtEnd = false

        laidOutSize = view.bounds.size
        laidOutSignature = content.signature
        laidOutInsets = insets
        lastContent = content
        if pageViewController == nil && currentPage == nil { rebuildContainer() }
        show(index: currentIndex, direction: nil)
    }

    private var lastContent: PagedContent?

    private func makePage(_ index: Int) -> PageContentController? {
        guard let content, pageRanges.indices.contains(index) else { return nil }
        let text = content.text.attributedSubstring(from: pageRanges[index])
        // 仿真翻頁會露出頁面背面，需要不透明的頁面色
        let color = transition == .curl ? pageColor : .clear
        return PageContentController(index: index, text: text, insets: insets, pageColor: color)
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
            pageViewController = controller
        case .cover, .fade:
            break
        }
    }

    private func show(index: Int, direction: UIPageViewController.NavigationDirection?) {
        guard let page = makePage(index) else { return }
        currentIndex = index
        if let pageViewController {
            pageViewController.setViewControllers([page], direction: direction ?? .forward, animated: direction != nil)
        } else {
            replaceCurrent(with: page, forward: direction.map { $0 == .forward }, animated: direction != nil)
        }
        notifyPageChange()
    }

    /// 覆蓋與淡入淡出動畫。
    private func replaceCurrent(with page: PageContentController, forward: Bool?, animated: Bool) {
        let old = currentPage
        addChild(page)
        page.view.frame = view.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        currentPage = page

        func finish() {
            old?.view.removeFromSuperview()
            old?.removeFromParent()
            page.didMove(toParent: self)
            isAnimating = false
        }

        guard animated, let old, let forward else {
            view.insertSubview(page.view, at: 0)
            finish()
            return
        }
        isAnimating = true
        let width = view.bounds.width

        switch transition {
        case .fade:
            page.view.alpha = 0
            view.insertSubview(page.view, aboveSubview: old.view)
            UIView.animate(withDuration: 0.3, animations: {
                page.view.alpha = 1
                old.view.alpha = 0
            }, completion: { _ in finish() })
        default:
            // 覆蓋：前進時新頁從右側蓋上；後退時舊頁向右滑開露出前一頁
            let moving = forward ? page.view : old.view
            moving.layer.shadowColor = UIColor.black.cgColor
            moving.layer.shadowOpacity = 0.25
            moving.layer.shadowRadius = 8
            if forward {
                page.view.frame.origin.x = width
                view.insertSubview(page.view, aboveSubview: old.view)
            } else {
                view.insertSubview(page.view, belowSubview: old.view)
            }
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
                if forward { page.view.frame.origin.x = 0 } else { old.view.frame.origin.x = width }
            }, completion: { _ in
                moving.layer.shadowOpacity = 0
                finish()
            })
        }
    }

    private func notifyPageChange() {
        guard let content, pageRanges.indices.contains(currentIndex) else { return }
        let range = pageRanges[currentIndex]
        let paragraphs = content.spans
            .filter { NSIntersectionRange($0.range, range).length > 0 }
            .map(\.paragraph)
        // 避免在 SwiftUI 更新期間修改狀態
        DispatchQueue.main.async { [weak self] in self?.onPageChange?(paragraphs) }
    }

    // MARK: Navigation

    private func turn(forward: Bool) {
        guard !isAnimating else { return }
        let target = currentIndex + (forward ? 1 : -1)
        guard pageRanges.indices.contains(target) else {
            onBoundary?(forward)
            return
        }
        show(index: target, direction: forward ? .forward : .reverse)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let x = recognizer.location(in: view).x
        let width = view.bounds.width
        if x < width * 0.3 { turn(forward: false) }
        else if x > width * 0.7 { turn(forward: true) }
        else { onCenterTap?() }
    }

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        // UIPageViewController 自己處理拖曳翻頁
        guard pageViewController == nil else { return }
        turn(forward: recognizer.direction == .left)
    }

    // MARK: UIPageViewController

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PageContentController else { return nil }
        return makePage(page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PageContentController else { return nil }
        return makePage(page.index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let page = pageViewController.viewControllers?.first as? PageContentController else { return }
        currentIndex = page.index
        notifyPageChange()
    }
}
