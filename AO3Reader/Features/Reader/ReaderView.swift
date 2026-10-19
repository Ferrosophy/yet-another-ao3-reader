import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderViewModel
    @Environment(AppState.self) private var app

    @AppStorage("reader.fontSize") private var fontSize = 18.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 6.0

    @State private var showsChrome = true
    @State private var showsChapters = false
    @State private var showsAppearance = false
    @Namespace private var glass

    init(model: ReaderViewModel) {
        _model = State(initialValue: model)
    }

    private var appearance: AppearanceSettings { app.appearance }

    private var style: ReaderStyle {
        ReaderStyle(fontSize: fontSize, lineSpacing: lineSpacing, font: appearance.config.readerFont)
    }

    var body: some View {
        content
            .background { ReaderBackground(appearance: appearance) }
            // 控制列以 overlay 疊在內容上，顯示 / 隱藏不改變內容的安全區域，避免捲動位置跳動
            .overlay(alignment: .bottom) {
                if showsChrome, model.detail != nil {
                    controls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: showsChrome)
            .environment(\.colorScheme, appearance.readerColorScheme ?? colorScheme)
            .navigationTitle(model.chapter?.title ?? model.route.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task { await model.load() }
            .sheet(isPresented: $showsChapters) {
                ChapterListSheet(model: model)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsAppearance) {
                ReaderAppearanceSheet(model: model, fontSize: $fontSize, lineSpacing: $lineSpacing)
                    .presentationDetents([.medium, .large])
            }
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let detail = model.detail, let chapter = model.chapter {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: style.lineSpacing * 2 + 8) {
                    header(detail: detail, chapter: chapter)
                        .id(ReaderViewModel.headerID(model.chapterIndex))
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
                // scrollTargetLayout + scrollPosition：上方段落高度變化（譯文載入）時，
                // 以目前頂端段落為錨點保持位置，不會被往上或往下推
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 96)
            }
            .scrollPosition(id: $model.scrollAnchor, anchor: .top)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onTapGesture { showsChrome.toggle() }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { old, new in
                // 只在明確的捲動方向上切換，忽略回彈區域
                guard new > 0 else { showsChrome = true; return }
                if new - old > 24 { showsChrome = false }
                else if old - new > 24 { showsChrome = true }
            }
        } else if let error = model.loadError {
            ContentUnavailableView {
                Label("無法開啟作品", systemImage: model.requiresLogin ? "lock" : "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ProgressView("載入中…")
        }
    }

    private func header(detail: WorkDetail, chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.chapterIndex == 0 {
                Text(detail.title)
                    .font(style.titleFont)
                Text(detail.authors.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                if !detail.series.isEmpty {
                    ForEach(detail.series, id: \.path) { series in
                        NavigationLink(value: WorkListRoute.series(name: series.name, path: series.path)) {
                            Label(series.name, systemImage: "books.vertical")
                                .font(.subheadline)
                        }
                    }
                }
                if !detail.tagGroups.isEmpty {
                    WorkTagsView(groups: detail.tagGroups)
                }
                if !detail.summary.isEmpty {
                    Text(detail.summary)
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
            }
            if detail.chapters.count > 1 {
                Text(chapter.title)
                    .font(style.headingFont)
                    .padding(.top, 8)
            }
        }
    }

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

    // MARK: - Liquid Glass controls

    /// 浮動控制列：多個玻璃元件置於同一 GlassEffectContainer，彼此靠近時會融合，
    /// 開啟翻譯時語言膠囊從翻譯按鈕「流出」（glassEffectID 形變動畫）。
    private var controls: some View {
        VStack(spacing: 8) {
            if let error = model.translationError, model.isTranslationOn {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.red.opacity(0.25)), in: .capsule)
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    circleButton("chevron.left", label: "上一章", enabled: model.hasPrevious) {
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
                    .font(.title3)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Button {
                        withAnimation(.bouncy) { model.isTranslationOn.toggle() }
                    } label: {
                        Image(systemName: "translate")
                            .font(.title3)
                            .foregroundStyle(model.isTranslationOn ? .white : .primary)
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(
                        model.isTranslationOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .circle
                    )
                    .glassEffectID("translate", in: glass)
                    .accessibilityLabel(model.isTranslationOn ? "關閉翻譯" : "開啟翻譯")

                    if model.isTranslationOn {
                        languageMenu
                            .glassEffectID("language", in: glass)
                    }

                    circleButton("chevron.right", label: "下一章", enabled: model.hasNext) {
                        model.nextChapter()
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var languageMenu: some View {
        Menu {
            Picker("目標語言", selection: Binding(get: { model.targetLanguage.code }, set: { model.setTargetLanguage($0) })) {
                ForEach(TranslationLanguage.all) { Text($0.name).tag($0.code) }
            }
            Picker("顯示方式", selection: Binding(get: { model.displayMode }, set: { model.setDisplayMode($0) })) {
                ForEach(BilingualDisplayMode.allCases) { Text($0.title).tag($0) }
            }
            Button("重新翻譯本章", systemImage: "arrow.clockwise") { model.resetTranslations() }
        } label: {
            Text(model.targetLanguage.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 48)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func circleButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 48, height: 48)
        }
        .disabled(!enabled)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

// MARK: - Background

/// 閱讀頁背景：系統預設、純色或使用者上傳的圖片（覆蓋一層系統背景色以確保文字可讀）。
struct ReaderBackground: View {
    let appearance: AppearanceSettings

    var body: some View {
        switch appearance.config.readerBackground {
        case .system:
            Color(.systemBackground).ignoresSafeArea()
        case .color:
            appearance.readerColor.ignoresSafeArea()
        case .image:
            if let image = appearance.backgroundImage {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(Color(.systemBackground).opacity(appearance.config.readerImageDim))
                }
                .ignoresSafeArea()
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }
        }
    }
}

// MARK: - Tags

/// 作品頁的標籤分組；點擊標籤查看該標籤下的所有作品（可再篩選）。
private struct WorkTagsView: View {
    let groups: [WorkTagGroup]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(expanded ? groups : Array(groups.prefix(4)), id: \.title) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(group.tags, id: \.path) { tag in
                            NavigationLink(value: WorkListRoute.tag(name: tag.name, path: tag.path)) {
                                Text(tag.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .fixedSize()
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                    }
                }
            }
            if groups.count > 4 {
                Button(expanded ? "收起標籤" : "顯示全部標籤") {
                    withAnimation { expanded.toggle() }
                }
                .font(.caption)
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

struct ReaderAppearanceSheet: View {
    let model: ReaderViewModel
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double

    var body: some View {
        NavigationStack {
            Form {
                Section("排版") {
                    LabeledContent("字級 \(Int(fontSize))") {
                        Slider(value: $fontSize, in: 14...30, step: 1)
                    }
                    LabeledContent("行距 \(Int(lineSpacing))") {
                        Slider(value: $lineSpacing, in: 0...16, step: 1)
                    }
                }
                ReaderAppearanceSections()
                Section("翻譯") {
                    Picker("顯示方式", selection: Binding(get: { model.displayMode }, set: { model.setDisplayMode($0) })) {
                        ForEach(BilingualDisplayMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("閱讀設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
