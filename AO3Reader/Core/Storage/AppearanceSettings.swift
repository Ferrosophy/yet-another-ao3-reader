import CoreText
import Observation
import SwiftUI
import UIKit

enum AppColorScheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟隨系統"
        case .light: "淺色"
        case .dark: "深色"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ReaderBackgroundKind: String, Codable, Sendable {
    case system, color, image
}

/// 背景圖淡化方式：疊白（變亮）或疊黑（變暗）。
enum DimStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case lighten, darken
    var id: String { rawValue }
    var title: String { self == .lighten ? "加亮" : "加暗" }
}

/// 單一外觀模式（淺色或深色）下的閱讀頁配色。
struct ReaderTheme: Codable, Equatable, Sendable {
    var background: ReaderBackgroundKind = .system
    var backgroundHex: String
    /// nil 為依背景自動選擇深 / 淺文字
    var textHex: String?
    var imageDim = 0.45
    var dimStyle: DimStyle

    static let defaultLight = ReaderTheme(backgroundHex: "#F4ECD8", dimStyle: .lighten)
    static let defaultDark = ReaderTheme(backgroundHex: "#1C1C1E", dimStyle: .darken)
}

enum ReaderFontWeight: String, CaseIterable, Codable, Identifiable, Sendable {
    case light, regular, medium, semibold, bold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "細"
        case .regular: "標準"
        case .medium: "中"
        case .semibold: "半粗"
        case .bold: "粗"
        }
    }
    var font: Font.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
    var uiFont: UIFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

enum ReadingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case scroll, paged
    var id: String { rawValue }
    var title: String { self == .scroll ? "捲動" : "翻頁" }
}

enum PageTransition: String, CaseIterable, Codable, Identifiable, Sendable {
    case curl, slide, cover, fade
    var id: String { rawValue }
    var title: String {
        switch self {
        case .curl: "仿真"
        case .slide: "平滑"
        case .cover: "覆蓋"
        case .fade: "淡入淡出"
        }
    }
}

/// 閱讀時頂欄（標題、狀態列）與底部控制列的行為。
enum ChromeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case floating, pinned
    var id: String { rawValue }
    var title: String { self == .floating ? "浮動（自動隱藏）" : "鎖定（常駐）" }
}

struct ReaderLayout: Codable, Hashable, Sendable {
    var fontSize = 18.0
    var fontWeight: ReaderFontWeight = .regular
    var lineSpacing = 6.0
    var paragraphSpacing = 14.0
    var letterSpacing = 0.0
    var horizontalMargin = 20.0
    /// 翻頁模式的上下邊距
    var verticalMargin = 28.0
    var mode: ReadingMode = .scroll
    var pageTransition: PageTransition = .curl
    var chrome: ChromeMode = .floating
}

/// 譯文顯示外觀。
struct TranslationAppearance: Codable, Hashable, Sendable {
    enum Style: String, CaseIterable, Codable, Identifiable, Sendable {
        case bar, card, plain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bar: "側條"
            case .card: "卡片"
            case .plain: "純文字"
            }
        }
    }

    var style: Style = .bar
    var fontScale = 0.95
    /// nil 為次要文字色
    var colorHex: String?
    var italic = false
}

/// 使用者匯入的字體檔（.ttf / .otf），存於 Application Support/Fonts。
struct CustomFont: Codable, Hashable, Identifiable, Sendable {
    var fileName: String
    var postScriptName: String
    var displayName: String
    var id: String { postScriptName }
}

struct AppearanceConfig: Codable, Equatable, Sendable {
    var colorScheme: AppColorScheme = .system
    var accentHex = "#990000"  // 書房紅
    var lightTheme = ReaderTheme.defaultLight
    var darkTheme = ReaderTheme.defaultDark
    /// "system" / "serif" / "rounded" / "family:<字族名稱>" / "custom:<PostScript 名稱>"
    var readerFont = "system"
    var customFonts: [CustomFont] = []
    var layout = ReaderLayout()
    var translation = TranslationAppearance()
}

/// 介面外觀與閱讀頁外觀設定，全部只存於本機。
@MainActor
@Observable
final class AppearanceSettings {
    var config: AppearanceConfig {
        didSet { if config != oldValue { save() } }
    }
    private(set) var backgroundImages: [Bool: UIImage] = [:]

    static let defaultAccent = "#990000"
    static let accentPresets: [(name: String, hex: String)] = [
        ("書房紅", "#990000"),
        ("燈塔金", "#E0A84A"),
        ("海軍藍", "#2F4A7A"),
    ]

    static let backgroundPresets: [(name: String, hex: String)] = [
        ("紙白", "#FBFAF7"),
        ("羊皮紙", "#F4ECD8"),
        ("護眼綠", "#CCE8CF"),
        ("淺灰", "#E9E9EB"),
        ("深海", "#1B2333"),
        ("夜間", "#1C1C1E"),
        ("純黑", "#000000"),
    ]

    static let textPresets: [(name: String, hex: String)] = [
        ("墨黑", "#1C1C1E"),
        ("深棕", "#4A3B2A"),
        ("深灰", "#3A3A3C"),
        ("米白", "#E8E2D0"),
        ("淺灰", "#C7C7CC"),
        ("純白", "#FFFFFF"),
    ]

    private let defaults: UserDefaults
    private static let key = "appearance.config.v2"
    private static let directory = URL.applicationSupportDirectory
    private static var fontsDirectory: URL { directory.appending(path: "Fonts", directoryHint: .isDirectory) }
    private static func backgroundURL(dark: Bool) -> URL {
        directory.appending(path: dark ? "reader-background-dark.jpg" : "reader-background-light.jpg")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var config = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(AppearanceConfig.self, from: $0) } ?? AppearanceConfig()
        if !Self.accentPresets.contains(where: { $0.hex == config.accentHex }) {
            config.accentHex = Self.defaultAccent
        }
        self.config = config
        try? FileManager.default.createDirectory(at: Self.fontsDirectory, withIntermediateDirectories: true)
        for font in config.customFonts {
            Self.register(Self.fontsDirectory.appending(path: font.fileName))
        }
        for dark in [false, true] {
            if let data = try? Data(contentsOf: Self.backgroundURL(dark: dark)) {
                backgroundImages[dark] = UIImage(data: data)
            }
        }
    }

    var accentColor: Color { Color(hex: config.accentHex) ?? Color(red: 0.6, green: 0, blue: 0) }

    // MARK: - Themes

    func theme(for scheme: ColorScheme) -> ReaderTheme {
        scheme == .dark ? config.darkTheme : config.lightTheme
    }

    func setTheme(_ theme: ReaderTheme, for scheme: ColorScheme) {
        if scheme == .dark { config.darkTheme = theme } else { config.lightTheme = theme }
    }

    func backgroundImage(for scheme: ColorScheme) -> UIImage? {
        backgroundImages[scheme == .dark]
    }

    /// 閱讀正文顏色：自訂色優先，否則依背景亮度自動決定；系統背景時回傳 nil（使用系統主色）。
    func textColor(for scheme: ColorScheme) -> Color? {
        let theme = theme(for: scheme)
        if let hex = theme.textHex, let color = Color(hex: hex) { return color }
        switch theme.background {
        case .system: return nil
        case .color: return Color.luminance(hex: theme.backgroundHex) < 0.5 ? .white : Color(white: 0.1)
        case .image:
            return theme.dimStyle == .darken ? .white : Color(white: 0.1)
        }
    }

    func setBackgroundImage(_ data: Data, for scheme: ColorScheme) throws {
        guard let image = UIImage(data: data) else { throw AppearanceError.invalidImage }
        let scaled = image.downscaled(maxDimension: 2400)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { throw AppearanceError.invalidImage }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try jpeg.write(to: Self.backgroundURL(dark: scheme == .dark), options: .atomic)
        backgroundImages[scheme == .dark] = scaled
        var theme = theme(for: scheme)
        theme.background = .image
        setTheme(theme, for: scheme)
    }

    // MARK: - Fonts

    /// 系統內建字族（含中文的蘋方、宋體、楷體等），按名稱排序。
    static let systemFontFamilies: [String] = UIFont.familyNames.sorted()

    var fontDisplayName: String {
        let value = config.readerFont
        if value == "system" { return "系統預設" }
        if value == "serif" { return "系統襯線" }
        if value == "rounded" { return "系統圓體" }
        if value.hasPrefix("family:") { return String(value.dropFirst("family:".count)) }
        if value.hasPrefix("custom:") {
            let name = String(value.dropFirst("custom:".count))
            return config.customFonts.first { $0.postScriptName == name }?.displayName ?? name
        }
        return value
    }

    /// 匯入字體：複製到 App 目錄並以 process 範圍註冊（不影響系統其他 App）。
    @discardableResult
    func importFont(from url: URL) throws -> CustomFont {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // 讀成 Data 再寫入，避免跨容器 copyItem 在部分檔案提供者上失敗
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AppearanceError.unreadableFile(error.localizedDescription)
        }
        guard let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider),
              let postScriptName = cgFont.postScriptName as String?
        else { throw AppearanceError.invalidFont }

        let fileName = url.lastPathComponent
        let destination = Self.fontsDirectory.appending(path: fileName)
        try FileManager.default.createDirectory(at: Self.fontsDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            Self.unregister(destination)
            try FileManager.default.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)
        Self.register(destination)

        let displayName = (cgFont.fullName as String?) ?? postScriptName
        let font = CustomFont(fileName: fileName, postScriptName: postScriptName, displayName: displayName)
        config.customFonts.removeAll { $0.postScriptName == postScriptName || $0.fileName == fileName }
        config.customFonts.append(font)
        config.readerFont = "custom:\(postScriptName)"
        return font
    }

    func removeFont(_ font: CustomFont) {
        let url = Self.fontsDirectory.appending(path: font.fileName)
        Self.unregister(url)
        try? FileManager.default.removeItem(at: url)
        config.customFonts.removeAll { $0 == font }
        if config.readerFont == "custom:\(font.postScriptName)" { config.readerFont = "system" }
    }

    private static func register(_ url: URL) {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func unregister(_ url: URL) {
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(config), forKey: Self.key)
    }
}

enum AppearanceError: LocalizedError {
    case invalidImage, invalidFont, unreadableFile(String)
    var errorDescription: String? {
        switch self {
        case .invalidImage: "無法讀取這張圖片"
        case .invalidFont: "無法讀取字體檔，請選擇 .ttf 或 .otf 檔案"
        case .unreadableFile(let reason): "無法讀取檔案：\(reason)"
        }
    }
}

// MARK: - Helpers

extension Color {
    init?(hex: String) {
        guard let rgb = Self.rgb(hex: hex) else { return nil }
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// 轉為 "#RRGGBB"（忽略透明度）。
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    static func luminance(hex: String) -> Double {
        guard let rgb = rgb(hex: hex) else { return 1 }
        return 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
    }

    private static func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

private extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
