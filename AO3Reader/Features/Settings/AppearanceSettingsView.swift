import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 設定 → 外觀：深色模式、主題色，以及閱讀頁的模式、排版、字體、配色與譯文外觀。
struct AppearanceSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var appearance = app.appearance

        ReaderAppearanceForm {
            Section("介面") {
                Picker("外觀模式", selection: $appearance.config.colorScheme) {
                    ForEach(AppColorScheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 20) {
                    ForEach(AppearanceSettings.accentPresets, id: \.hex) { preset in
                        Swatch(color: Color(hex: preset.hex) ?? .red, label: LocalizedStringKey(preset.name),
                               isSelected: appearance.config.accentHex == preset.hex) {
                            appearance.config.accentHex = preset.hex
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                NavigationLink {
                    FontPickerView(title: "介面字體", selection: Binding(
                        get: { appearance.interfaceFontChoice },
                        set: { appearance.config.interfaceFont = $0 == "system" ? nil : $0 }
                    ))
                } label: {
                    LabeledContent("介面字體", value: appearance.displayName(forFont: appearance.interfaceFontChoice))
                }
            }
        } trailing: {
            EmptyView()
        }
        .navigationTitle("外觀")
    }
}

/// 閱讀頁外觀表單，設定頁與閱讀頁的「閱讀設定」共用。
/// 圖片選擇器與錯誤提示掛在 Form 上（而非 Section），確保在 sheet 中也能正常彈出。
struct ReaderAppearanceForm<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var systemScheme
    @State private var editingScheme: ColorScheme?
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    private var scheme: ColorScheme { editingScheme ?? systemScheme }

    var body: some View {
        @Bindable var appearance = app.appearance
        let layout = $appearance.config.layout
        let theme = Binding(
            get: { appearance.theme(for: scheme) },
            set: { appearance.setTheme($0, for: scheme) }
        )

        Form {
            leading

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

            Section("排版") {
                slider("字級", value: layout.fontSize, in: 12...34, step: 1)
                Picker("字重", selection: layout.fontWeight) {
                    ForEach(ReaderFontWeight.allCases) { Text($0.title).tag($0) }
                }
                slider("行距", value: layout.lineSpacing, in: 0...20, step: 1)
                slider("段落間距", value: layout.paragraphSpacing, in: 0...40, step: 1)
                slider("字間距", value: layout.letterSpacing, in: -1...6, step: 0.5)
                slider("左右邊距", value: layout.horizontalMargin, in: 8...60, step: 2)
                if appearance.config.layout.mode == .paged {
                    slider("上下邊距", value: layout.verticalMargin, in: 8...100, step: 2)
                }
            }

            Section("字體") {
                NavigationLink {
                    FontPickerView(title: "閱讀字體", selection: $appearance.config.readerFont)
                } label: {
                    LabeledContent("閱讀字體", value: appearance.fontDisplayName)
                }
            }

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
                }
                ColorPicker("自訂背景色", selection: Binding(
                    get: { Color(hex: theme.wrappedValue.backgroundHex) ?? .white },
                    set: {
                        theme.wrappedValue.backgroundHex = $0.hexString
                        theme.wrappedValue.background = .color
                    }
                ), supportsOpacity: false)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(appearance.backgroundImage(for: scheme) == nil ? "選擇背景圖片" : "更換背景圖片", systemImage: "photo")
                }
                if appearance.backgroundImage(for: scheme) != nil, theme.wrappedValue.background != .image {
                    Button("使用背景圖片", systemImage: "photo.fill") { theme.wrappedValue.background = .image }
                }
                if theme.wrappedValue.background == .image {
                    Picker("淡化方式", selection: theme.dimStyle) {
                        ForEach(DimStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    slider("淡化程度", value: theme.imageDim, in: 0...0.95, step: 0.05, percent: true)
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
                }
                ColorPicker("自訂文字色", selection: Binding(
                    get: { theme.wrappedValue.textHex.flatMap(Color.init(hex:)) ?? .primary },
                    set: { theme.wrappedValue.textHex = $0.hexString }
                ), supportsOpacity: false)
            } header: {
                Text("文字顏色")
            } footer: {
                Text("「自動」會依背景深淺選擇黑色或白色文字。")
            }

            Section("譯文外觀") {
                Picker("樣式", selection: $appearance.config.translation.style) {
                    ForEach(TranslationAppearance.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("譯文字級", value: $appearance.config.translation.fontScale, in: 0.7...1.2, step: 0.05, percent: true)
                Toggle("斜體", isOn: $appearance.config.translation.italic)
                ColorPicker("譯文顏色", selection: Binding(
                    get: { appearance.config.translation.colorHex.flatMap(Color.init(hex:)) ?? .secondary },
                    set: { appearance.config.translation.colorHex = $0.hexString }
                ), supportsOpacity: false)
                if appearance.config.translation.colorHex != nil {
                    Button("譯文顏色恢復預設") { appearance.config.translation.colorHex = nil }
                }
            }

            trailing
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

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, percent: Bool = false) -> some View {
        let display = percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : value.wrappedValue.formatted(.number.precision(.fractionLength(0...1)))
        return LabeledContent {
            Slider(value: value, in: range, step: step)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text(verbatim: display).monospacedDigit()
            }
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
                    Button("匯入字體檔（TTF / OTF）", systemImage: "square.and.arrow.down") { importing = true }
                } header: {
                    Text("已匯入")
                } footer: {
                    Text("從「檔案」選擇字體檔，僅在本 App 內使用；向左滑可刪除。")
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
