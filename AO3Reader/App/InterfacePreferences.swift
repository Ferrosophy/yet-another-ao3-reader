import SwiftUI
import UIKit

/// 介面語言：20 種主流語言，繁體中文再分台灣、香港、澳門。
/// 透過 AppleLanguages 指定 App 語言（與 iOS「設定 → App → 語言」相同機制），重新啟動 App 後完整生效。
struct InterfaceLanguage: Identifiable, Hashable {
    let code: String
    /// 以該語言自稱顯示
    let name: String
    var id: String { code }

    static let all: [InterfaceLanguage] = [
        .init(code: "en", name: "English"),
        .init(code: "zh-Hans", name: "简体中文"),
        .init(code: "zh-Hant-TW", name: "繁體中文（台灣）"),
        .init(code: "zh-Hant-HK", name: "繁體中文（香港）"),
        .init(code: "zh-Hant-MO", name: "繁體中文（澳門）"),
        .init(code: "ja", name: "日本語"),
        .init(code: "ko", name: "한국어"),
        .init(code: "es", name: "Español"),
        .init(code: "fr", name: "Français"),
        .init(code: "de", name: "Deutsch"),
        .init(code: "pt-BR", name: "Português (Brasil)"),
        .init(code: "it", name: "Italiano"),
        .init(code: "ru", name: "Русский"),
        .init(code: "uk", name: "Українська"),
        .init(code: "pl", name: "Polski"),
        .init(code: "tr", name: "Türkçe"),
        .init(code: "nl", name: "Nederlands"),
        .init(code: "ar", name: "العربية"),
        .init(code: "hi", name: "हिन्दी"),
        .init(code: "id", name: "Bahasa Indonesia"),
        .init(code: "vi", name: "Tiếng Việt"),
        .init(code: "th", name: "ไทย"),
    ]

    private static let key = "app.interfaceLanguage"

    /// 目前實際使用的介面語言代碼（跟隨系統時取 App 實際載入的語系）
    static var currentCode: String {
        selectedCode ?? Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// 介面是否為英文（英文介面不需要再附上術語的英文原文）
    static var isEnglish: Bool { currentCode.hasPrefix("en") }

    /// nil 為跟隨系統
    static var selectedCode: String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func select(_ code: String?) {
        let defaults = UserDefaults.standard
        if let code {
            defaults.set(code, forKey: key)
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}

/// 介面字體（與閱讀字體分開）。值的格式與閱讀字體相同：
/// "system" / "serif" / "rounded" / "family:<字族>" / "custom:<PostScript 名稱>"。
enum InterfaceFont {
    static func font(_ choice: String, style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let base: Font
        if let name = customName(choice) {
            base = .custom(name, size: size(for: style), relativeTo: style)
        } else {
            base = .system(style, design: design(choice))
        }
        if let weight { return base.weight(weight) }
        return style == .headline && customName(choice) != nil ? base.weight(.semibold) : base
    }

    static func design(_ choice: String) -> Font.Design {
        switch choice {
        case "serif": .serif
        case "rounded": .rounded
        default: .default
        }
    }

    static func customName(_ choice: String) -> String? {
        if choice.hasPrefix("family:") { return String(choice.dropFirst("family:".count)) }
        if choice.hasPrefix("custom:") { return String(choice.dropFirst("custom:".count)) }
        return nil
    }

    /// iOS 預設（Large 字級）的各文字樣式大小，自訂字體會再隨動態字級縮放
    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    /// 導覽列標題由 UIKit 繪製，另行套用。
    @MainActor
    static func applyNavigationBarAppearance(_ choice: String) {
        let appearance = UINavigationBar.appearance()
        guard let name = customName(choice) else {
            appearance.titleTextAttributes = nil
            appearance.largeTitleTextAttributes = nil
            return
        }
        let title = UIFont(name: name, size: 17) ?? UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: name]), size: 17)
        let large = UIFont(name: name, size: 34) ?? UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: name]), size: 34)
        appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)]
        appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
    }
}

private struct InterfaceFontKey: EnvironmentKey {
    static let defaultValue = "system"
}

extension EnvironmentValues {
    var interfaceFont: String {
        get { self[InterfaceFontKey.self] }
        set { self[InterfaceFontKey.self] = newValue }
    }
}

private struct AppFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    @Environment(\.interfaceFont) private var choice

    func body(content: Content) -> some View {
        content.font(InterfaceFont.font(choice, style: style, weight: weight))
    }
}

extension View {
    /// 依「介面字體」設定套用文字樣式（取代 `.font(.headline)` 等）。
    func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(AppFontModifier(style: style, weight: weight))
    }
}

/// AO3 特有術語：在非英文介面時附上官網的英文原文（例如「簡介 Summary」），方便對照官網。
struct AO3TermLabel: View {
    let title: LocalizedStringKey
    let english: String

    var body: some View {
        if InterfaceLanguage.isEnglish {
            Text(verbatim: english)
        } else {
            Text("\(Text(title)) \(Text(verbatim: english).foregroundStyle(.secondary))")
        }
    }
}

enum AO3Term {
    /// 字串版本：「配對 Relationships」；英文介面或兩者相同時只顯示一個
    static func label(_ localized: String, _ english: String) -> String {
        if InterfaceLanguage.isEnglish || localized.caseInsensitiveCompare(english) == .orderedSame { return english }
        return "\(localized) \(english)"
    }
}
