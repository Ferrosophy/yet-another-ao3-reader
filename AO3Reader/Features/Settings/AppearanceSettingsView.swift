import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 設定 → 外觀 → 某一個分類（介面、閱讀模式、字體與排版、閱讀配色、標籤與簡介、譯文外觀）。
/// 設定頁把六個分類直接列在「外觀」下；閱讀頁的「閱讀設定」仍使用選項卡。
struct AppearanceSettingsView: View {
    let tab: AppearanceTab
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var systemScheme
    @State private var accentScheme: ColorScheme?

    var body: some View {
        @Bindable var appearance = app.appearance
        let scheme = accentScheme ?? systemScheme

        ReaderAppearanceForm(showsInterface: true, fixedTab: tab) {
            Section {
                Picker("外觀模式", selection: $appearance.config.colorScheme) {
                    ForEach(AppColorScheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("編輯", selection: Binding(get: { scheme }, set: { accentScheme = $0 })) {
                    Text("淺色模式").tag(ColorScheme.light)
                    Text("深色模式").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 20) {
                    ForEach(AppearanceSettings.accentPresets, id: \.hex) { preset in
                        Swatch(color: Color(hex: preset.hex) ?? .red, label: LocalizedStringKey(preset.name),
                               isSelected: appearance.accentHex(for: scheme) == preset.hex) {
                            appearance.setAccentHex(preset.hex, for: scheme)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text("主題色")
            } footer: {
                Text("淺色與深色模式各自保存主題色，跟隨系統切換。")
            }

        } translationExtras: {
            EmptyView()
        }
        .navigationTitle(tab.title)
    }
}

/// 外觀設定的分類選項卡。
enum AppearanceTab: String, CaseIterable, Identifiable {
    case interface, mode, typography, colors, tags, translation

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .interface: "介面"
        case .mode: "閱讀模式"
        case .typography: "字體與排版"
        case .colors: "閱讀配色"
        case .tags: "標籤與簡介"
        case .translation: "譯文外觀"
        }
    }

    var systemImage: String {
        switch self {
        case .interface: "iphone"
        case .mode: "book.pages"
        case .typography: "textformat"
        case .colors: "paintpalette"
        case .tags: "tag"
        case .translation: "translate"
        }
    }
}

/// 閱讀頁外觀表單，設定頁與閱讀頁的「閱讀設定」共用，依選項卡分類顯示。
/// 圖片選擇器與錯誤提示掛在 Form 上（而非 Section），確保在 sheet 中也能正常彈出。
struct ReaderAppearanceForm<Interface: View, TranslationExtras: View>: View {
    private let showsInterface: Bool
    private let interface: Interface
    private let translationExtras: TranslationExtras

    /// - Parameters:
    ///   - showsInterface: 是否顯示「介面」選項卡（設定頁）
    ///   - translationExtras: 「譯文外觀」選項卡頂部的額外設定（閱讀頁的顯示方式）
    ///   - fixedTab: 只顯示這個分類、不顯示選項卡列（設定頁的各分類頁面）
    init(showsInterface: Bool = false, fixedTab: AppearanceTab? = nil, @ViewBuilder interface: () -> Interface,
         @ViewBuilder translationExtras: () -> TranslationExtras) {
        self.showsInterface = showsInterface
        self.fixedTab = fixedTab
        self.interface = interface()
        self.translationExtras = translationExtras()
        _tab = State(initialValue: fixedTab ?? (showsInterface ? .interface : .mode))
    }

    private let fixedTab: AppearanceTab?

    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var systemScheme
    @State private var tab: AppearanceTab
    @State private var editingScheme: ColorScheme?
    /// 「字體與排版」正在編輯的模式；nil 為目前的閱讀模式
    @State private var typographyMode: ReadingMode?
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    private var scheme: ColorScheme { editingScheme ?? systemScheme }
    private var tabs: [AppearanceTab] { AppearanceTab.allCases.filter { showsInterface || $0 != .interface } }

    var body: some View {
        @Bindable var appearance = app.appearance
        let layout = $appearance.config.layout
        let theme = Binding(
            get: { appearance.theme(for: scheme) },
            set: { appearance.setTheme($0, for: scheme) }
        )

        Form {
            if fixedTab == nil {
                Section {
                    AppearanceTabBar(tabs: tabs, selection: $tab)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch tab {
            case .interface:
                interface
            case .mode:
                modeSections(layout: layout)
            case .typography:
                Section("字體") {
                    NavigationLink {
                        FontPickerView(title: "閱讀字體", selection: $appearance.config.readerFont)
                    } label: {
                        LabeledContent("閱讀字體", value: appearance.fontDisplayName)
                    }
                }
                typographySections
            case .colors:
                colorSections(theme: theme)
            case .tags:
                tagSections
            case .translation:
                translationExtras
                translationSections
            }
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            let target = scheme
            Task {
                do {
                    if let data = try await photoItem.loadTransferable(type: Data.self) {
                        try appearance.setBackgroundImage(data, for: target)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                self.photoItem = nil
            }
        }
        .alert("無法套用", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func modeSections(layout: Binding<ReaderLayout>) -> some View {
        let appearance = app.appearance
        Section("閱讀模式") {
            Picker("模式", selection: layout.mode) {
                ForEach(ReadingMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if appearance.config.layout.mode == .paged {
                Picker("翻頁動畫", selection: layout.pageTransition) {
                    ForEach(PageTransition.allCases) { Text($0.title).tag($0) }
                }
            }
            Picker("標題列與控制列", selection: layout.chrome) {
                ForEach(ChromeMode.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    @ViewBuilder
    private var typographySections: some View {
        let appearance = app.appearance
        let mode = typographyMode ?? appearance.config.layout.mode
        let layout = Binding(
            get: { appearance.layout(for: mode) },
            set: { appearance.setLayout($0, for: mode) }
        )
        Section {
            Picker("編輯", selection: Binding(get: { mode }, set: { typographyMode = $0 })) {
                ForEach(ReadingMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("滾動與翻頁模式各自保存排版；相同的數值在兩種模式下顯示效果一致。")
        }

        Section("排版") {
            Picker("字體粗細", selection: layout.fontWeight) {
                ForEach(ReaderFontWeight.allCases) { Text($0.title).tag($0) }
            }
            slider("字體大小", value: layout.fontSize, in: 10...40, step: 1)
            slider("行距", value: layout.lineSpacing, in: 0...20, step: 1)
            slider("字間距", value: layout.letterSpacing, in: -1...6, step: 0.1)
            slider("段落間距", value: layout.paragraphSpacing, in: 0...40, step: 1)
            slider("左右邊距", value: layout.horizontalMargin, in: 0...80, step: 1)
            if mode == .paged {
                slider("上下邊距", value: layout.verticalMargin, in: 0...120, step: 1)
            }
        }

        Section {
            Button("恢復預設排版") { appearance.resetLayout(for: mode) }
                .disabled(appearance.isDefaultLayout(for: mode))
        } footer: {
            Text("只恢復目前編輯的模式（滾動或翻頁）的排版數值，字體與其他設定不變。")
        }
    }

    @ViewBuilder
    private func colorSections(theme: Binding<ReaderTheme>) -> some View {
        let appearance = app.appearance
        let hasBackgroundImage = appearance.backgroundImage(for: scheme) != nil
        Section {
            Picker("編輯", selection: Binding(get: { scheme }, set: { editingScheme = $0 })) {
                Text("淺色模式").tag(ColorScheme.light)
                Text("深色模式").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("配色")
        } footer: {
            Text("淺色與深色模式各自保存背景與文字顏色，跟隨系統切換。")
        }

        Section("背景") {
            SwatchRow {
                Swatch(color: Color(.systemBackground), label: "預設",
                       isSelected: theme.wrappedValue.background == .system) {
                    theme.wrappedValue.background = .system
                }
                ForEach(AppearanceSettings.backgroundPresets, id: \.hex) { preset in
                    Swatch(color: Color(hex: preset.hex) ?? .white, label: LocalizedStringKey(preset.name),
                           isSelected: theme.wrappedValue.background == .color && theme.wrappedValue.backgroundHex == preset.hex) {
                        theme.wrappedValue.backgroundHex = preset.hex
                        theme.wrappedValue.background = .color
                    }
                }
                // 自訂顏色放在色票列末尾
                CustomColorSwatch(isSelected: theme.wrappedValue.background == .color && !AppearanceSettings.backgroundPresets.contains { $0.hex == theme.wrappedValue.backgroundHex }, selection: Binding(
                    get: { Color(hex: theme.wrappedValue.backgroundHex) ?? .white },
                    set: {
                        theme.wrappedValue.backgroundHex = $0.hexString
                        theme.wrappedValue.background = .color
                    }
                ))
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(hasBackgroundImage ? LocalizedStringKey("更換背景圖片") : "選擇背景圖片", systemImage: "photo")
            }
            if appearance.backgroundImage(for: scheme) != nil, theme.wrappedValue.background != .image {
                Button("使用背景圖片", systemImage: "photo.fill") { theme.wrappedValue.background = .image }
            }
            if theme.wrappedValue.background == .image {
                Picker("淡化方式", selection: theme.dimStyle) {
                    ForEach(DimStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("淡化程度", value: theme.imageDim, in: 0...0.95, step: 0.01, percent: true)
            }
        }

        Section {
            SwatchRow {
                Swatch(color: .gray, label: "自動", isSelected: theme.wrappedValue.textHex == nil, symbol: "wand.and.stars") {
                    theme.wrappedValue.textHex = nil
                }
                ForEach(AppearanceSettings.textPresets, id: \.hex) { preset in
                    Swatch(color: Color(hex: preset.hex) ?? .black, label: LocalizedStringKey(preset.name),
                           isSelected: theme.wrappedValue.textHex == preset.hex) {
                        theme.wrappedValue.textHex = preset.hex
                    }
                }
                // 自訂顏色放在色票列末尾
                CustomColorSwatch(isSelected: theme.wrappedValue.textHex.map { hex in !AppearanceSettings.textPresets.contains { $0.hex == hex } } ?? false, selection: Binding(
                    get: { theme.wrappedValue.textHex.flatMap(Color.init(hex:)) ?? .primary },
                    set: { theme.wrappedValue.textHex = $0.hexString }
                ))
            }
        } header: {
            Text("文字顏色")
        } footer: {
            Text("「自動」會依背景深淺選擇黑色或白色文字。")
        }
    }

    @ViewBuilder
    private var tagSections: some View {
        @Bindable var appearance = app.appearance
        Section {
            SwatchRow {
                Swatch(color: .gray, label: "自動", isSelected: appearance.config.tagBackgroundHex == nil, symbol: "wand.and.stars") {
                    appearance.config.tagBackgroundHex = nil
                }
                ForEach(AppearanceSettings.tagBackgroundPresets, id: \.hex) { preset in
                    Swatch(color: Color(hex: preset.hex) ?? .gray, label: LocalizedStringKey(preset.name),
                           isSelected: appearance.config.tagBackgroundHex == preset.hex) {
                        appearance.config.tagBackgroundHex = preset.hex
                    }
                }
                // 自訂顏色放在色票列末尾
                CustomColorSwatch(isSelected: appearance.config.tagBackgroundHex.map { hex in !AppearanceSettings.tagBackgroundPresets.contains { $0.hex == hex } } ?? false, selection: Binding(
                    get: { appearance.config.tagBackgroundHex.flatMap(Color.init(hex:)) ?? Color.primary.opacity(0.08) },
                    set: { appearance.config.tagBackgroundHex = $0.hexString }
                ))
            }
        } header: {
            Text("標籤與簡介背景")
        } footer: {
            Text("自動配色會依正文顏色產生淡色底，與閱讀背景融為一體。")
        }

        Section {
            SwatchRow {
                Swatch(color: .gray, label: "自動", isSelected: appearance.config.tagTextHex == nil, symbol: "wand.and.stars") {
                    appearance.config.tagTextHex = nil
                }
                ForEach(AppearanceSettings.textPresets, id: \.hex) { preset in
                    Swatch(color: Color(hex: preset.hex) ?? .black, label: LocalizedStringKey(preset.name),
                           isSelected: appearance.config.tagTextHex == preset.hex) {
                        appearance.config.tagTextHex = preset.hex
                    }
                }
                // 自訂顏色放在色票列末尾
                CustomColorSwatch(isSelected: appearance.config.tagTextHex.map { hex in !AppearanceSettings.textPresets.contains { $0.hex == hex } } ?? false, selection: Binding(
                    get: { appearance.config.tagTextHex.flatMap(Color.init(hex:)) ?? .primary },
                    set: { appearance.config.tagTextHex = $0.hexString }
                ))
            }
        } header: {
            Text("標籤與簡介文字")
        } footer: {
            Text("「自動」與正文顏色相同。")
        }
    }

    @ViewBuilder
    private var translationSections: some View {
        @Bindable var appearance = app.appearance
        Section("譯文外觀") {
            Picker("樣式", selection: $appearance.config.translation.style) {
                ForEach(TranslationAppearance.Style.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("譯文大小跟隨正文", isOn: Binding(
                get: { appearance.config.translation.followsFontSize == true },
                set: { appearance.config.translation.followsFontSize = $0 }
            ))
            if appearance.config.translation.followsFontSize != true {
                slider("譯文大小", value: $appearance.config.translation.fontScale, in: 0.6...1.3, step: 0.01, percent: true)
            }
            Toggle("斜體", isOn: $appearance.config.translation.italic)
        }

        Section {
            let translation = appearance.config.translation
            let followsText = translation.followsTextColor == true
            SwatchRow {
                Swatch(color: .gray, label: "預設", isSelected: translation.colorHex == nil && !followsText, symbol: "wand.and.stars") {
                    appearance.config.translation.colorHex = nil
                    appearance.config.translation.followsTextColor = false
                }
                Swatch(color: appearance.textColor(for: scheme) ?? .primary, label: "跟隨正文", isSelected: followsText,
                       symbol: "textformat") {
                    appearance.config.translation.colorHex = nil
                    appearance.config.translation.followsTextColor = true
                }
                CustomColorSwatch(isSelected: translation.colorHex != nil && !followsText, selection: Binding(
                    get: { translation.colorHex.flatMap(Color.init(hex:)) ?? .secondary },
                    set: {
                        appearance.config.translation.colorHex = $0.hexString
                        appearance.config.translation.followsTextColor = false
                    }
                ))
            }
        } header: {
            Text("譯文顏色")
        } footer: {
            Text("「預設」為較淡的次要文字色；「跟隨正文」與目前閱讀配色的正文顏色相同。")
        }
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, percent: Bool = false) -> some View {
        FineSlider(title: title, value: value, range: range, step: step, percent: percent)
    }
}

/// 帶「−」「＋」微調按鈕的滑桿：標題欄固定寬度，讓每一列的標題、滑桿與數值左右對齊。
struct FineSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// 滑桿與按鈕的最小單位（百分比項目為 0.01，即 1%）
    let step: Double
    var percent = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(width: 84, alignment: .leading)
            nudge("minus", by: -step)
            Slider(value: $value, in: range, step: step)
            nudge("plus", by: step)
            Text(verbatim: display)
                .appFont(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var display: String {
        if percent { return "\(Int((value * 100).rounded()))%" }
        return value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0)))
    }

    private func nudge(_ symbol: String, by delta: Double) -> some View {
        Button {
            // 以步長為單位取整，避免浮點誤差累積（例如 0.30000000004）
            let next = ((value + delta) / step).rounded() * step
            value = min(max(next, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: symbol)
                .appFont(.caption, weight: .bold)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(delta < 0 ? value <= range.lowerBound : value >= range.upperBound)
        .accessibilityLabel(delta < 0 ? Text("減少") : Text("增加"))
    }
}

/// 外觀設定的選項卡列：可橫向捲動的玻璃按鈕。
private struct AppearanceTabBar: View {
    let tabs: [AppearanceTab]
    @Binding var selection: AppearanceTab

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        Group {
                            if tab == selection {
                                Button { select(tab, proxy) } label: { label(tab) }
                                    .buttonStyle(.glassProminent)
                            } else {
                                Button { select(tab, proxy) } label: { label(tab) }
                                    .buttonStyle(.glass)
                            }
                        }
                        .id(tab)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
    }

    private func label(_ tab: AppearanceTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
            .appFont(.subheadline, weight: .medium)
            .lineLimit(1)
    }

    private func select(_ tab: AppearanceTab, _ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            selection = tab
            proxy.scrollTo(tab, anchor: .center)
        }
    }
}

/// 字體選擇：系統預設、蘋果內建字族與自行匯入的 TTF / OTF。
struct FontPickerView: View {
    let title: LocalizedStringKey
    @Binding var selection: String
    @Environment(AppState.self) private var app
    @State private var search = ""
    @State private var importing = false
    @State private var cloudDrive: CloudDrive?
    @State private var errorMessage: String?

    private static let sample = "Aa 永字八法 あア"
    private static let importTypes: [UTType] = [.font] + ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        let appearance = app.appearance
        let families = AppearanceSettings.systemFontFamilies.filter {
            search.isEmpty || $0.localizedCaseInsensitiveContains(search)
        }

        List {
            if search.isEmpty {
                Section("系統") {
                    row("system", title: "系統預設（San Francisco / 蘋方）", font: .system(size: 17))
                    row("serif", title: "系統襯線（New York / 宋體）", font: .system(size: 17, design: .serif))
                    row("rounded", title: "系統圓體", font: .system(size: 17, design: .rounded))
                }

                Section {
                    ForEach(appearance.config.customFonts) { font in
                        row("custom:\(font.postScriptName)", title: LocalizedStringKey(font.displayName), font: .custom(font.postScriptName, size: 17))
                    }
                    .onDelete { offsets in
                        for index in offsets { appearance.removeFont(appearance.config.customFonts[index]) }
                    }
                    Button("從本機檔案匯入（TTF / OTF）", systemImage: "square.and.arrow.down") { importing = true }
                    Menu {
                        ForEach(CloudDrive.allCases) { drive in
                            Button(drive.title) { cloudDrive = drive }
                        }
                    } label: {
                        Label("從雲端硬碟匯入", systemImage: "icloud.and.arrow.down")
                    }
                } header: {
                    Text("已匯入")
                } footer: {
                    Text("可從「檔案」或雲端硬碟（Google Drive、OneDrive、PikPak、百度網盤、夸克網盤、阿里雲盤）匯入字體檔，僅在本 App 內使用；向左滑可刪除。")
                }
            }

            Section("蘋果內建字體") {
                ForEach(families, id: \.self) { family in
                    row("family:\(family)", title: LocalizedStringKey(family), font: .custom(family, size: 17))
                }
            }
        }
        .searchable(text: $search, prompt: "搜尋字體")
        .navigationTitle(title)
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let font = try appearance.importFont(from: url)
                selection = "custom:\(font.postScriptName)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $cloudDrive) { drive in
            CloudFontImportView(drive: drive) { font in selection = "custom:\(font.postScriptName)" }
        }
        .alert("無法匯入字體", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ value: String, title: LocalizedStringKey, font: Font) -> some View {
        Button {
            selection = value
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).appFont(.subheadline).foregroundStyle(.secondary)
                    Text(Self.sample).font(font).foregroundStyle(.primary)
                }
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}

/// 可橫向捲動的色票列：取消 List 列的內縮，讓內容在整列寬度內捲動，不會與左右邊界錯位。
private struct SwatchRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) { content }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .listRowInsets(EdgeInsets())
    }
}

/// 色票列末尾的「自訂」色環：點擊開啟系統調色盤；目前顏色不屬於預設色票時顯示為選中。
private struct CustomColorSwatch: View {
    let isSelected: Bool
    @Binding var selection: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                // 直接顯示系統的色環按鈕（點擊開啟調色盤）；不可用透明疊加，否則點擊不會觸發
                ColorPicker("自訂", selection: $selection, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.2)
            }
            .frame(width: 46, height: 46)
            Text("自訂").appFont(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 圓形色票，選中時外圈高亮；外圈包含在框架內，不會被裁切。
private struct Swatch: View {
    let color: Color
    let label: LocalizedStringKey
    let isSelected: Bool
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    Circle()
                        .fill(color)
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                        .padding(5)
                    if let symbol {
                        Image(systemName: symbol).appFont(.caption).foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
                Text(label).appFont(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
