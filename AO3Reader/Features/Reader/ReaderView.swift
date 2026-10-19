import SwiftUI
import UIKit

struct ReaderView: View {
    @State private var model: ReaderViewModel
    @State private var actions: WorkActionsModel
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    @State private var showsChrome = true
    @State private var showsChapters = false
    @State private var showsAppearance = false
    @State private var showsTranslationSettings = false
    @State private var showsSourcePicker = false
    /// 翻頁模式往前翻到上一章時，從該章最後一頁開始
    @State private var startAtEnd = false
    /// 顯示控制列時量到的安全區域；內容以固定邊距排版，控制列出現 / 隱藏不會推動正文
    @State private var topInset: CGFloat = 0
    @State private var bottomInset: CGFloat = 0
    @State private var pagedCache = PagedContentCache()
    @Namespace private var glass

    init(model: ReaderViewModel) {
        _model = State(initialValue: model)
        _actions = State(initialValue: WorkActionsModel(workID: model.route.id, client: model.client))
    }

    private var appearance: AppearanceSettings { app.appearance }
    private var layout: ReaderLayout { appearance.config.layout }
    private var chromeVisible: Bool { layout.chrome == .pinned || showsChrome }

    private var style: ReaderStyle {
        ReaderStyle(
            layout: layout,
            font: appearance.config.readerFont,
            textColor: appearance.textColor(for: colorScheme),
            translation: appearance.config.translation
        )
    }

    var body: some View {
        ZStack {
            ReaderBackground(appearance: appearance, scheme: colorScheme)
            content
        }
        .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { insets in
            topInset = max(topInset, insets.top)
            bottomInset = max(bottomInset, insets.bottom)
        }
        .overlay(alignment: .bottom) {
            if chromeVisible, model.detail != nil {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) { toast }
        .animation(.smooth(duration: 0.25), value: chromeVisible)
        .navigationTitle(model.chapter?.title ?? model.route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!chromeVisible)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if app.auth.isLoggedIn { WorkActionsMenu(model: actions) }
            }
        }
        .task { await model.load() }
        .task(id: model.detail?.id) {
            if let detail = model.detail { await actions.load(from: detail) }
        }
        .sheet(isPresented: $showsChapters) {
            ChapterListSheet(model: model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsAppearance) {
            NavigationStack {
                ReaderAppearanceForm {
                    EmptyView()
                } translationExtras: {
                    Section("譯文顯示") {
                        Picker("顯示方式", selection: Binding(get: { model.displayMode }, set: { model.setDisplayMode($0) })) {
                            ForEach(BilingualDisplayMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .navigationTitle("閱讀設定")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $model.challenge, onDismiss: { model.resetTranslations() }) { challenge in
            TranslationChallengeView(challenge: challenge)
        }
        .sheet(isPresented: $showsSourcePicker) {
            TranslationLanguageSheet(title: "原文語言", languages: app.translation.config.provider.sourceLanguages, allowsAutomatic: true,
                                selection: Binding(get: { model.sourceLanguage?.code }, set: { model.setSourceLanguage($0) }))
        }
        .sheet(isPresented: $showsTranslationSettings, onDismiss: { model.resetTranslations() }) {
            NavigationStack {
                TranslationSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showsTranslationSettings = false }
                        }
                    }
            }
        }
    }

    private func toggleChrome() {
        guard layout.chrome == .floating else { return }
        showsChrome.toggle()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let detail = model.detail, let chapter = model.chapter {
            switch layout.mode {
            case .scroll: scrollContent(detail: detail, chapter: chapter)
            case .paged: pagedContent(detail: detail, chapter: chapter)
            }
        } else if let error = model.loadError {
            ContentUnavailableView {
                Label("無法開啟作品", systemImage: model.requiresLogin ? "lock" : "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            AO3LoadingView()
        }
    }

    private func scrollContent(detail: WorkDetail, chapter: Chapter) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: layout.paragraphSpacing) {
                header(detail: detail, chapter: chapter)
                    .id(ReaderViewModel.headerID(model.chapterIndex))
                    .onAppear { model.headerAppeared() }
                    .onDisappear { model.headerDisappeared() }
                ForEach(chapter.paragraphs) { paragraph in
                    BilingualParagraphView(
                        paragraph: paragraph,
                        translation: model.translations[paragraph.id],
                        showsTranslation: model.isTranslationOn,
                        mode: model.displayMode,
                        style: style,
                        onRetry: { model.retry(paragraph) }
                    )
                    .onAppear { model.paragraphAppeared(paragraph) }
                    .onDisappear { model.paragraphDisappeared(paragraph) }
                }
                chapterFooter
            }
            // 上方段落高度變化（譯文載入）時，以頂端段落為錨點保持位置
            .scrollTargetLayout()
            .padding(.horizontal, layout.horizontalMargin)
            .foregroundStyle(style.textColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
        }
        .scrollPosition(id: $model.scrollAnchor, anchor: .top)
        .contentMargins(.top, topInset + 12, for: .scrollContent)
        .contentMargins(.bottom, bottomInset + 96, for: .scrollContent)
        .ignoresSafeArea(edges: .vertical)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onTapGesture { toggleChrome() }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { old, new in
            guard layout.chrome == .floating else { return }
            if new <= 0 { showsChrome = true }
            else if new - old > 24 { showsChrome = false }
            else if old - new > 24 { showsChrome = true }
        }
    }

    private func pagedContent(detail: WorkDetail, chapter: Chapter) -> some View {
        let textColor = style.textColor.map(UIColor.init) ?? .label
        let secondary = style.textColor.map { UIColor($0).withAlphaComponent(0.65) } ?? .secondaryLabel
        var hasher = Hasher()
        hasher.combine(model.chapterIndex)
        hasher.combine(model.isTranslationOn)
        hasher.combine(model.displayMode)
        hasher.combine(model.translations)
        hasher.combine(layout)
        hasher.combine(appearance.config.translation)
        hasher.combine(appearance.config.readerFont)
        hasher.combine(textColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)).hashValue)
        let signature = hasher.finalize()

        let content = pagedCache.content(signature: signature) {
            let (text, spans) = PagedTextBuilder.build(
                title: model.chapterIndex == 0 ? detail.title : nil,
                summary: model.chapterIndex == 0 && !detail.summary.isEmpty ? detail.summary : nil,
                chapterTitle: detail.chapters.count > 1 ? chapter.title : nil,
                chapterIndex: model.chapterIndex,
                chapter: chapter,
                translations: model.translations,
                showsTranslation: model.isTranslationOn,
                mode: model.displayMode,
                style: style,
                textColor: textColor,
                secondaryColor: secondary
            )
            return PagedContent(signature: signature, chapterIndex: model.chapterIndex, text: text, spans: spans)
        }

        let theme = appearance.theme(for: colorScheme)
        let pageColor: UIColor = theme.background == .color
            ? UIColor(Color(hex: theme.backgroundHex) ?? .white)
            : .systemBackground

        return PagedReaderView(
            content: content,
            transition: layout.pageTransition,
            insets: UIEdgeInsets(
                top: topInset + layout.verticalMargin,
                left: layout.horizontalMargin,
                bottom: bottomInset + layout.verticalMargin + (layout.chrome == .pinned ? 64 : 0),
                right: layout.horizontalMargin
            ),
            pageColor: pageColor,
            anchorParagraphID: model.scrollAnchor,
            startAtEnd: startAtEnd,
            onPageChange: { paragraphs in
                model.setVisibleParagraphs(paragraphs)
                if let first = paragraphs.first { model.scrollAnchor = first.id }
            },
            onCenterTap: { withAnimation { toggleChrome() } },
            onBoundary: { forward in
                if forward, model.hasNext {
                    startAtEnd = false
                    model.nextChapter()
                } else if !forward, model.hasPrevious {
                    startAtEnd = true
                    model.previousChapter()
                }
            }
        )
        .ignoresSafeArea()
    }

    private func header(detail: WorkDetail, chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.chapterIndex == 0 {
                Text(detail.title)
                    .font(style.titleFont)
                Text(detail.authors.joined(separator: ", "))
                    .foregroundStyle(bodyColor.opacity(0.7))
                if !detail.series.isEmpty {
                    ForEach(detail.series, id: \.path) { series in
                        NavigationLink(value: WorkListRoute.series(name: series.name, path: series.path)) {
                            Label(series.name, systemImage: "books.vertical")
                                .appFont(.subheadline)
                                .foregroundStyle(bodyColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !detail.tagGroups.isEmpty {
                    WorkTagsView(groups: detail.tagGroups, background: cardBackground, foreground: cardForeground)
                }
                if !detail.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.summary)
                            .appFont(.callout)
                            .foregroundStyle(cardForeground)
                        metaTranslation(ReaderViewModel.summaryID, font: style.font(scale: 0.9 * style.translation.fontScale))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground, in: .rect(cornerRadius: 14))
                }
            }
            if detail.chapters.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chapter.title)
                        .font(style.headingFont)
                    metaTranslation(ReaderViewModel.chapterTitleID(model.chapterIndex),
                                    font: style.font(scale: 1.1 * style.translation.fontScale, weight: .semibold))
                }
                .padding(.top, 8)
            }
        }
    }

    /// 標題與簡介的沉浸式譯文（顯示在原文下方，不取代原文）
    @ViewBuilder
    private func metaTranslation(_ id: String, font: Font) -> some View {
        if model.isTranslationOn {
            ImmersiveTranslationView(translation: model.translations[id], style: style, font: font) {
                model.retryMeta(id)
            }
        }
    }

    /// 標籤與簡介的底色：自訂色或正文顏色的淡色，與閱讀背景融為一體
    private var cardBackground: Color {
        appearance.config.tagBackgroundHex.flatMap(Color.init(hex:)) ?? bodyColor.opacity(0.08)
    }

    /// 標籤與簡介的文字：自訂色，否則與正文同色
    private var cardForeground: Color {
        appearance.config.tagTextHex.flatMap(Color.init(hex:)) ?? bodyColor
    }

    /// 正文顏色（未自訂時為系統主要文字色）
    private var bodyColor: Color { style.textColor ?? .primary }

    private var chapterFooter: some View {
        HStack {
            if model.hasPrevious {
                Button("上一章", systemImage: "chevron.left") { model.previousChapter() }
            }
            Spacer()
            if model.hasNext {
                Button("下一章", systemImage: "chevron.right") { model.nextChapter() }
                    .buttonStyle(.glassProminent)
            }
        }
        .buttonStyle(.glass)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var toast: some View {
        if let message = actions.message {
            Text(message)
                .appFont(.subheadline, weight: .medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, topInset + 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { actions.message = nil }
                }
        }
    }

    // MARK: - Liquid Glass controls

    /// 浮動控制列：多個玻璃元件置於同一 GlassEffectContainer，彼此靠近時會融合，
    /// 開啟翻譯時語言膠囊從翻譯按鈕「流出」（glassEffectID 形變動畫）。長按翻譯按鈕可直接開啟翻譯設定。
    private var controls: some View {
        VStack(spacing: 8) {
            if let error = model.translationError, model.isTranslationOn {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.caption)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.red.opacity(0.25)), in: .capsule)
                    .onTapGesture { showsTranslationSettings = true }
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    circleButton("chevron.left", label: "上一章", enabled: model.hasPrevious) {
                        startAtEnd = false
                        model.previousChapter()
                    }

                    HStack(spacing: 18) {
                        Button { showsChapters = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("章節")
                        Button { showsAppearance = true } label: {
                            Image(systemName: "textformat.size")
                        }
                        .accessibilityLabel("閱讀設定")
                    }
                    .appFont(.title3)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Button {
                        withAnimation(.bouncy) { model.isTranslationOn.toggle() }
                    } label: {
                        Image(systemName: "translate")
                            .appFont(.title3)
                            .foregroundStyle(model.isTranslationOn ? .white : .primary)
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(
                        model.isTranslationOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .circle
                    )
                    .glassEffectID("translate", in: glass)
                    .contextMenu {
                        Button("翻譯設定", systemImage: "gearshape") { showsTranslationSettings = true }
                    }
                    .accessibilityLabel(model.isTranslationOn ? "關閉翻譯" : "開啟翻譯")
                    .accessibilityHint("長按開啟翻譯設定")

                    if model.isTranslationOn {
                        languageMenu
                            .glassEffectID("language", in: glass)
                    }

                    circleButton("chevron.right", label: "下一章", enabled: model.hasNext) {
                        startAtEnd = false
                        model.nextChapter()
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var languageMenu: some View {
        Menu {
            Button {
                showsSourcePicker = true
            } label: {
                Label("原文語言", systemImage: "character.book.closed")
                Text(verbatim: model.sourceLanguage?.displayName ?? String(localized: "自動偵測"))
            }
            Picker("目標語言", selection: Binding(get: { model.targetLanguage.code }, set: { model.setTargetLanguage($0) })) {
                ForEach(TranslationLanguage.all) { Text($0.name).tag($0.code) }
            }
            .pickerStyle(.menu)
            Picker("顯示方式", selection: Binding(get: { model.displayMode }, set: { model.setDisplayMode($0) })) {
                ForEach(BilingualDisplayMode.allCases) { Text($0.title).tag($0) }
            }
            Button("重新翻譯本章", systemImage: "arrow.clockwise") { model.resetTranslations() }
            Button("翻譯設定…", systemImage: "gearshape") { showsTranslationSettings = true }
        } label: {
            Text(model.targetLanguage.name)
                .appFont(.subheadline, weight: .medium)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 48)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func circleButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(.title3)
                .frame(width: 48, height: 48)
        }
        .disabled(!enabled)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// 翻頁內容快取：同一簽章不重複建立整章的 NSAttributedString。
final class PagedContentCache {
    private var cached: PagedContent?

    func content(signature: Int, build: () -> PagedContent) -> PagedContent {
        if let cached, cached.signature == signature { return cached }
        let content = build()
        cached = content
        return content
    }
}

// MARK: - Background

/// 閱讀頁背景：依目前淺色 / 深色模式套用各自的設定（系統、純色或圖片）。
struct ReaderBackground: View {
    let appearance: AppearanceSettings
    let scheme: ColorScheme

    var body: some View {
        let theme = appearance.theme(for: scheme)
        Group {
            switch theme.background {
            case .system:
                Color(.systemBackground)
            case .color:
                Color(hex: theme.backgroundHex) ?? Color(.systemBackground)
            case .image:
                if let image = appearance.backgroundImage(for: scheme) {
                    GeometryReader { proxy in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .overlay((theme.dimStyle == .darken ? Color.black : Color.white).opacity(theme.imageDim))
                    }
                } else {
                    Color(.systemBackground)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Tags

/// 作品頁的標籤分組；點擊標籤查看該標籤下的所有作品（可再篩選）。
private struct WorkTagsView: View {
    let groups: [WorkTagGroup]
    let background: Color
    let foreground: Color
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(expanded ? groups : Array(groups.prefix(4)), id: \.title) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(foreground.opacity(0.65))
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(group.tags, id: \.path) { tag in
                            NavigationLink(value: WorkListRoute.tag(name: tag.name, path: tag.path)) {
                                Text(tag.name)
                                    .appFont(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(foreground)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(background, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if groups.count > 4 {
                Button(expanded ? "收起標籤" : "顯示全部標籤") {
                    withAnimation { expanded.toggle() }
                }
                .appFont(.caption)
            }
        }
    }
}

// MARK: - Sheets

struct ChapterListSheet: View {
    let model: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.detail?.chapters ?? []) { chapter in
                Button {
                    model.goToChapter(chapter.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                        Spacer()
                        if chapter.id == model.chapterIndex {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("章節")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
