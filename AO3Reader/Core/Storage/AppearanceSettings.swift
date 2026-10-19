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

/// 使用者匯入的字體檔（.ttf / .otf），存於 Application Support/Fonts。
struct CustomFont: Codable, Hashable, Identifiable, Sendable {
    var fileName: String
    var postScriptName: String
    var displayName: String
    var id: String { postScriptName }
}

struct AppearanceConfig: Codable, Equatable, Sendable {
    var colorScheme: AppColorScheme = .system
    /// nil 為系統預設強調色
    var accentHex: String?
    var readerBackground: ReaderBackgroundKind = .system
    var readerColorHex = "#F4ECD8"
    /// 背景圖上覆蓋的系統背景色不透明度，確保文字可讀
    var readerImageDim = 0.55
    /// "system" / "serif" / "rounded" / "custom:<PostScript 名稱>"
    var readerFont = "serif"
    var customFonts: [CustomFont] = []
}

/// 介面外觀與閱讀頁外觀設定，全部只存於本機。
@MainActor
@Observable
final class AppearanceSettings {
    var config: AppearanceConfig {
        didSet { if config != oldValue { save() } }
    }
    private(set) var backgroundImage: UIImage?

    static let accentPresets: [(name: String, hex: String)] = [
        ("燈塔金", "#E0A84A"),
        ("海軍藍", "#2F4A7A"),
        ("天藍", "#0A84FF"),
        ("薄荷", "#30B0A0"),
        ("玫瑰", "#E05A7A"),
        ("紫羅蘭", "#8E6CEF"),
        ("橙", "#FF9F0A"),
    ]

    static let readerPresets: [(name: String, hex: String)] = [
        ("紙白", "#FBFAF7"),
        ("羊皮紙", "#F4ECD8"),
        ("護眼綠", "#CCE8CF"),
        ("淺灰", "#E9E9EB"),
        ("深海", "#1B2333"),
        ("夜間", "#1C1C1E"),
        ("純黑", "#000000"),
    ]

    private let defaults: UserDefaults
    private static let key = "appearance.config"
    private static let directory = URL.applicationSupportDirectory
    private static var fontsDirectory: URL { directory.appending(path: "Fonts", directoryHint: .isDirectory) }
    private static var backgroundURL: URL { directory.appending(path: "reader-background.jpg") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.config = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(AppearanceConfig.self, from: $0) } ?? AppearanceConfig()
        try? FileManager.default.createDirectory(at: Self.fontsDirectory, withIntermediateDirectories: true)
        for font in config.customFonts {
            Self.register(Self.fontsDirectory.appending(path: font.fileName))
        }
        if let data = try? Data(contentsOf: Self.backgroundURL) {
            backgroundImage = UIImage(data: data)
        }
    }

    var accentColor: Color? { config.accentHex.flatMap(Color.init(hex:)) }

    // MARK: - Reader background

    var readerColor: Color { Color(hex: config.readerColorHex) ?? .white }

    /// 純色背景時依亮度決定使用深色或淺色文字。
    var readerColorScheme: ColorScheme? {
        guard config.readerBackground == .color else { return nil }
        return Color.luminance(hex: config.readerColorHex) < 0.5 ? .dark : .light
    }

    func setBackgroundImage(_ data: Data) throws {
        guard let image = UIImage(data: data) else { throw AppearanceError.invalidImage }
        let scaled = image.downscaled(maxDimension: 2400)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { throw AppearanceError.invalidImage }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try jpeg.write(to: Self.backgroundURL, options: .atomic)
        backgroundImage = scaled
        config.readerBackground = .image
    }

    // MARK: - Custom fonts

    /// 匯入字體：複製到 App 目錄並以 process 範圍註冊（不影響系統其他 App）。
    @discardableResult
    func importFont(from url: URL) throws -> CustomFont {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let destination = Self.fontsDirectory.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path()) {
            Self.unregister(destination)
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        else {
            try? FileManager.default.removeItem(at: destination)
            throw AppearanceError.invalidFont
        }
        let displayName = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String ?? postScriptName
        Self.register(destination)

        let font = CustomFont(fileName: destination.lastPathComponent, postScriptName: postScriptName, displayName: displayName)
        config.customFonts.removeAll { $0.postScriptName == postScriptName || $0.fileName == font.fileName }
        config.customFonts.append(font)
        config.readerFont = "custom:\(postScriptName)"
        return font
    }

    func removeFont(_ font: CustomFont) {
        let url = Self.fontsDirectory.appending(path: font.fileName)
        Self.unregister(url)
        try? FileManager.default.removeItem(at: url)
        config.customFonts.removeAll { $0 == font }
        if config.readerFont == "custom:\(font.postScriptName)" { config.readerFont = "serif" }
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
    case invalidImage, invalidFont
    var errorDescription: String? {
        switch self {
        case .invalidImage: "無法讀取這張圖片"
        case .invalidFont: "無法讀取字體檔，請選擇 .ttf 或 .otf 檔案"
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
