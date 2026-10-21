import Foundation
import Observation

/// 一個 AO3 內容來源：官網或使用者導入的鏡像站。
struct AO3Source: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var baseURL: URL
    var isBuiltIn = false

    static let official = AO3Source(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000A030")!,
        name: String(localized: "Archive of Our Own（官網）"),
        baseURL: URL(string: "https://archiveofourown.org")!,
        isBuiltIn: true
    )
}

/// 管理來源列表與目前使用中的來源，保存在 UserDefaults（僅本機）。
@MainActor
@Observable
final class SourceStore {
    private(set) var sources: [AO3Source]
    var selectedID: AO3Source.ID {
        didSet { save() }
    }

    var selected: AO3Source {
        sources.first { $0.id == selectedID } ?? .official
    }

    private let defaults: UserDefaults
    private static let sourcesKey = "sources.list"
    private static let selectedKey = "sources.selected"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.sourcesKey)
            .flatMap { try? JSONDecoder().decode([AO3Source].self, from: $0) } ?? []
        self.sources = [.official] + stored.filter { !$0.isBuiltIn }
        let storedID = defaults.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:)) ?? AO3Source.official.id
        // 展示來源不保存：重新開啟 App 時回到官網
        self.selectedID = storedID == DemoSite.source.id ? AO3Source.official.id : storedID
    }

    /// 解析使用者輸入的網址，補齊 scheme 並去掉路徑。
    nonisolated static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host?.isEmpty == false
        else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    @discardableResult
    func add(name: String, url: URL) -> AO3Source {
        if let existing = sources.first(where: { $0.baseURL.host() == url.host() }) {
            return existing
        }
        let source = AO3Source(name: name.isEmpty ? (url.host() ?? url.absoluteString) : name, baseURL: url)
        sources.append(source)
        save()
        return source
    }

    /// 目前是否為展示模式（虛構的示範內容）
    var isDemo: Bool { selectedID == DemoSite.source.id }

    /// 加入或移除展示來源（不保存到來源列表）
    func setDemoListed(_ listed: Bool) {
        sources.removeAll { $0.id == DemoSite.source.id }
        if listed { sources.append(DemoSite.source) }
    }

    func remove(_ source: AO3Source) {
        guard !source.isBuiltIn else { return }
        sources.removeAll { $0.id == source.id }
        if selectedID == source.id { selectedID = AO3Source.official.id }
        save()
    }

    private func save() {
        let custom = sources.filter { !$0.isBuiltIn }
        defaults.set(try? JSONEncoder().encode(custom), forKey: Self.sourcesKey)
        defaults.set(selectedID.uuidString, forKey: Self.selectedKey)
    }
}
