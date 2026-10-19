import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderViewModel

    @AppStorage("reader.fontSize") private var fontSize = 18.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 6.0
    @AppStorage("reader.serif") private var serif = true

    @State private var showsChrome = true
    @State private var showsChapters = false
    @State private var showsAppearance = false
    @Namespace private var glass

    init(model: ReaderViewModel) {
        _model = State(initialValue: model)
    }

    private var style: ReaderStyle { ReaderStyle(fontSize: fontSize, lineSpacing: lineSpacing, serif: serif) }

    var body: some View {
        content
            .navigationTitle(model.chapter?.title ?? model.route.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsChrome ? .visible : .hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if showsChrome, model.detail != nil {
                    controls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: showsChrome)
            .task { await model.load() }
            .sheet(isPresented: $showsChapters) {
                ChapterListSheet(model: model)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsAppearance) {
                ReaderAppearanceSheet(model: model, fontSize: $fontSize, lineSpacing: $lineSpacing, serif: $serif)
                    .presentationDetents([.height(360)])
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let detail = model.detail, let chapter = model.chapter {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: style.lineSpacing * 2 + 8) {
                        header(detail: detail, chapter: chapter)
                            .id("top")
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .animation(.easeOut(duration: 0.2), value: model.translations)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onTapGesture { showsChrome.toggle() }
                // 往下捲動閱讀時收起控制列，往上捲時再出現
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { old, new in
                    if new - old > 16, new > 80 { showsChrome = false }
                    else if old - new > 16 { showsChrome = true }
                }
                .onChange(of: model.chapterIndex) {
                    proxy.scrollTo("top", anchor: .top)
                }
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
        VStack(alignment: .leading, spacing: 8) {
            if model.chapterIndex == 0 {
                Text(detail.title)
                    .font(.system(size: fontSize * 1.5, weight: .bold, design: serif ? .serif : .default))
                Text(detail.authors.joined(separator: ", "))
                    .foregroundStyle(.secondary)
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
    @Binding var serif: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("字體") {
                    LabeledContent("字級 \(Int(fontSize))") {
                        Slider(value: $fontSize, in: 14...30, step: 1)
                    }
                    LabeledContent("行距 \(Int(lineSpacing))") {
                        Slider(value: $lineSpacing, in: 0...16, step: 1)
                    }
                    Toggle("襯線字體", isOn: $serif)
                }
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
