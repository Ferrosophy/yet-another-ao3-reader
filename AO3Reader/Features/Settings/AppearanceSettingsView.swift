import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 設定 → 外觀：深色模式、主題色，以及閱讀頁的字體與背景。
struct AppearanceSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var appearance = app.appearance

        Form {
            Section("介面") {
                Picker("外觀模式", selection: $appearance.config.colorScheme) {
                    ForEach(AppColorScheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 10) {
                    Text("主題色")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            Swatch(color: .blue, label: "系統", isSelected: appearance.config.accentHex == nil) {
                                appearance.config.accentHex = nil
                            }
                            ForEach(AppearanceSettings.accentPresets, id: \.hex) { preset in
                                Swatch(color: Color(hex: preset.hex) ?? .blue, label: preset.name,
                                       isSelected: appearance.config.accentHex == preset.hex) {
                                    appearance.config.accentHex = preset.hex
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    ColorPicker("自訂主題色", selection: Binding(
                        get: { appearance.accentColor ?? .blue },
                        set: { appearance.config.accentHex = $0.hexString }
                    ), supportsOpacity: false)
                }
            }

            ReaderAppearanceSections()
        }
        .navigationTitle("外觀")
    }
}

/// 閱讀頁字體與背景設定，設定頁與閱讀頁的「閱讀設定」共用。
struct ReaderAppearanceSections: View {
    @Environment(AppState.self) private var app
    @State private var importsFont = false
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var appearance = app.appearance

        Section {
            Picker("字體", selection: $appearance.config.readerFont) {
                Text("系統").tag("system")
                Text("襯線").font(.system(.body, design: .serif)).tag("serif")
                Text("圓體").font(.system(.body, design: .rounded)).tag("rounded")
                ForEach(appearance.config.customFonts) { font in
                    Text(font.displayName).font(.custom(font.postScriptName, size: 17)).tag("custom:\(font.postScriptName)")
                }
            }
            ForEach(appearance.config.customFonts) { font in
                Label(font.displayName, systemImage: "textformat")
                    .font(.custom(font.postScriptName, size: 17))
            }
            .onDelete { offsets in
                for index in offsets { appearance.removeFont(appearance.config.customFonts[index]) }
            }
            Button("匯入字體檔（TTF / OTF）", systemImage: "square.and.arrow.down") { importsFont = true }
        } header: {
            Text("閱讀字體")
        } footer: {
            Text("字體只在本 App 內使用；向左滑可刪除已匯入的字體。")
        }
        .fileImporter(isPresented: $importsFont, allowedContentTypes: [.font], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                try appearance.importFont(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        Section("閱讀背景") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Swatch(color: Color(.systemBackground), label: "預設",
                           isSelected: appearance.config.readerBackground == .system) {
                        appearance.config.readerBackground = .system
                    }
                    ForEach(AppearanceSettings.readerPresets, id: \.hex) { preset in
                        Swatch(color: Color(hex: preset.hex) ?? .white, label: preset.name,
                               isSelected: appearance.config.readerBackground == .color && appearance.config.readerColorHex == preset.hex) {
                            appearance.config.readerColorHex = preset.hex
                            appearance.config.readerBackground = .color
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            ColorPicker("自訂背景色", selection: Binding(
                get: { appearance.readerColor },
                set: {
                    appearance.config.readerColorHex = $0.hexString
                    appearance.config.readerBackground = .color
                }
            ), supportsOpacity: false)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(appearance.backgroundImage == nil ? "選擇背景圖片" : "更換背景圖片", systemImage: "photo")
            }
            if appearance.backgroundImage != nil {
                Button("使用背景圖片", systemImage: "photo.fill") { appearance.config.readerBackground = .image }
                    .disabled(appearance.config.readerBackground == .image)
            }
            if appearance.config.readerBackground == .image {
                LabeledContent("圖片淡化 \(Int(appearance.config.readerImageDim * 100))%") {
                    Slider(value: $appearance.config.readerImageDim, in: 0...0.95)
                }
            }
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                do {
                    guard let data = try await photoItem.loadTransferable(type: Data.self) else { return }
                    try appearance.setBackgroundImage(data)
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
}

/// 圓形色票，選中時外圈高亮。
private struct Swatch: View {
    let color: Color
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0).padding(-4))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
