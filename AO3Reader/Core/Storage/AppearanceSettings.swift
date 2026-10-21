// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import Observation
import SwiftUI
import UIKit

enum AppColorScheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "跟隨系統")
        case .light: String(localized: "淺色")
        case .dark: String(localized: "深色")
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
    var title: String { self == .lighten ? String(localized: "加亮") : String(localized: "加暗") }
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
        case .light: String(localized: "細")
        case .regular: String(localized: "標準")
        case .medium: String(localized: "中")
        case .semibold: String(localized: "半粗")
        case .bold: String(localized: "粗")
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
    var title: String { self == .scroll ? String(localized: "滾動") : String(localized: "翻頁") }
}

enum PageTransition: String, CaseIterable, Codable, Identifiable, Sendable {
    case curl, slide, cover, fade
    var id: String { rawValue }
    var title: String {
        switch self {
        case .curl: String(localized: "仿真")
        case .slide: String(localized: "平滑")
        case .cover: String(localized: "覆蓋")
        case .fade: String(localized: "淡入淡出")
        }
    }
}

/// 閱讀時頂欄（標題、狀態列）與底部控制列的行為。
enum ChromeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case floating, pinned
    var id: String { rawValue }
    var title: String { self == .floating ? String(localized: "浮動") : String(localized: "鎖定") }
}

struct ReaderLayout: Codable, Hashable, Sendable {
    var fontSize = 18.0
    var fontWeight: ReaderFontWeight = .regular
    var lineSpacing = 6.0
    var paragraphSpacing = 14.0
    var letterSpacing = 0.0
    /// 舊版的左右 / 上下邊距；四邊分開設定後作為未設定時的預設值
    var horizontalMargin = 20.0
    /// 翻頁模式的上下邊距
    var verticalMargin = 28.0
    var mode: ReadingMode = .scroll
    var pageTransition: PageTransition = .curl
    var chrome: ChromeMode = .floating
    // 四邊分開的邊距（Optional 讓舊設定可正常解碼）
    var leftMarginValue: Double?
    var rightMarginValue: Double?
    var topMarginValue: Double?
    var bottomMarginValue: Double?

    var leftMargin: Double {
        get { leftMarginValue ?? horizontalMargin }
        set { leftMarginValue = newValue }
    }
    var rightMargin: Double {
        get { rightMarginValue ?? horizontalMargin }
        set { rightMarginValue = newValue }
    }
    /// 翻頁模式的上邊距
    var topMargin: Double {
        get { topMarginValue ?? verticalMargin }
        set { topMarginValue = newValue }
    }
    /// 翻頁模式的下邊距
    var bottomMargin: Double {
        get { bottomMarginValue ?? verticalMargin }
        set { bottomMarginValue = newValue }
    }
}

/// 譯文顯示外觀。
struct TranslationAppearance: Codable, Hashable, Sendable {
    enum Style: String, CaseIterable, Codable, Identifiable, Sendable {
        case bar, card, plain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bar: String(localized: "側條")
            case .card: String(localized: "卡片")
            case .plain: String(localized: "純文字")
            }
        }
    }

    var style: Style = .bar
    var fontScale = 0.95
    /// nil 為次要文字色
    var colorHex: String?
    /// 譯文與正文同色（Optional 讓舊設定可正常解碼）
    var followsTextColor: Bool?
    /// 譯文與正文字體大小相同（忽略 fontScale）
    var followsFontSize: Bool?

    /// 實際使用的譯文字級倍率
    var scale: Double { followsFontSize == true ? 1 : fontScale }
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
    /// 淺色模式的主題色
    var accentHex = "#990000"  // 書房紅
    /// 深色模式的主題色；nil 為與淺色模式相同
    var darkAccentHex: String?
    var lightTheme = ReaderTheme.defaultLight
    var darkTheme = ReaderTheme.defaultDark
    /// "system" / "serif" / "rounded" / "family:<字族名稱>" / "custom:<PostScript 名稱>"
    var readerFont = "system"
    /// 介面字體，與閱讀字體分開；nil 為系統預設（Optional 讓舊設定可正常解碼）
    var interfaceFont: String?
    /// 閱讀頁標籤膠囊與簡介框的背景 / 文字色；nil 為依正文顏色自動
    var tagBackgroundHex: String?
    var tagTextHex: String?
    var customFonts: [CustomFont] = []
    /// 閱讀模式、翻頁動畫、控制列，以及滾動模式的排版
    var layout = ReaderLayout()
    /// 翻頁模式自己的排版（字體大小、行距、邊距等）；nil 時沿用滾動模式的數值（Optional 讓舊設定可正常解碼）
    var pagedLayout: ReaderLayout?
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

    /// 標籤與簡介的底色預設（淺色系用於淺色背景，深色系用於深色背景）
    static let tagBackgroundPresets: [(name: String, hex: String)] = [
        ("淺米", "#EFE6D2"),
        ("淺灰", "#E5E5EA"),
        ("淺藍", "#DCE6F2"),
        ("淺綠", "#DDEBDD"),
        ("深灰", "#2C2C2E"),
        ("深藍", "#22304A"),
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
        if let dark = config.darkAccentHex, !Self.accentPresets.contains(where: { $0.hex == dark }) {
            config.darkAccentHex = nil
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

    /// 介面主題色：淺色與深色模式各自設定，隨系統外觀自動切換
    var accentColor: Color {
        let fallback = UIColor(red: 0.6, green: 0, blue: 0, alpha: 1)
        let light = Color(hex: config.accentHex).map(UIColor.init) ?? fallback
        let dark = (config.darkAccentHex ?? config.accentHex)
        let darkColor = Color(hex: dark).map(UIColor.init) ?? light
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkColor : light })
    }

    func accentHex(for scheme: ColorScheme) -> String {
        scheme == .dark ? (config.darkAccentHex ?? config.accentHex) : config.accentHex
    }

    func setAccentHex(_ hex: String, for scheme: ColorScheme) {
        if scheme == .dark { config.darkAccentHex = hex } else { config.accentHex = hex }
    }

    // MARK: - 排版

    /// 指定閱讀模式的排版；模式、翻頁動畫與控制列設定一律取共用值
    func layout(for mode: ReadingMode) -> ReaderLayout {
        guard mode == .paged else { return config.layout }
        var paged = config.pagedLayout ?? config.layout
        paged.mode = config.layout.mode
        paged.pageTransition = config.layout.pageTransition
        paged.chrome = config.layout.chrome
        return paged
    }

    /// 目前閱讀模式實際使用的排版
    var readerLayout: ReaderLayout { layout(for: config.layout.mode) }

    /// 預設排版：18pt、標準粗細、行距 6、字間距 0、段落間距 14、左右邊距 20；
    /// 翻頁模式的上下邊距已另外包含瀏海與 Home 指示條的安全區域，所以預設 16 即可
    static func defaultLayout(for mode: ReadingMode) -> ReaderLayout {
        var layout = ReaderLayout()
        if mode == .paged { layout.verticalMargin = 16 }
        layout.leftMargin = layout.horizontalMargin
        layout.rightMargin = layout.horizontalMargin
        layout.topMargin = layout.verticalMargin
        layout.bottomMargin = layout.verticalMargin
        return layout
    }

    /// 指定模式的預設排版，保留目前的閱讀模式、翻頁動畫與控制列設定
    private func defaultsKeepingMode(for mode: ReadingMode) -> ReaderLayout {
        var layout = Self.defaultLayout(for: mode)
        layout.mode = config.layout.mode
        layout.pageTransition = config.layout.pageTransition
        layout.chrome = config.layout.chrome
        return layout
    }

    func isDefaultLayout(for mode: ReadingMode) -> Bool {
        layout(for: mode) == defaultsKeepingMode(for: mode)
    }

    /// 把指定模式的排版恢復預設（不影響閱讀模式、翻頁動畫與控制列設定）
    func resetLayout(for mode: ReadingMode) {
        setLayout(defaultsKeepingMode(for: mode), for: mode)
    }

    func setLayout(_ layout: ReaderLayout, for mode: ReadingMode) {
        if mode == .paged { config.pagedLayout = layout } else { config.layout = layout }
    }

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

    var fontDisplayName: String { displayName(forFont: config.readerFont) }

    /// 介面一律使用系統字體（已移除介面字體自訂；欄位保留以相容舊設定）
    var interfaceFontChoice: String { "system" }

    func displayName(forFont value: String) -> String {
        if value == "system" { return String(localized: "系統預設") }
        if value == "serif" { return String(localized: "系統襯線") }
        if value == "rounded" { return String(localized: "系統圓體") }
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
        case .invalidImage: String(localized: "無法讀取這張圖片")
        case .invalidFont: String(localized: "無法讀取字體檔，請選擇 .ttf 或 .otf 檔案")
        case .unreadableFile(let reason): String(localized: "無法讀取檔案：\(reason)")
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
