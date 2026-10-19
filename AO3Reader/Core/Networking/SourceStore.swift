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
        self.selectedID = defaults.string(forKey: Self.selectedKey)
            .flatMap(UUID.init(uuidString:)) ?? AO3Source.official.id
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

    /// 批次導入：每行一個網址，可選「名稱 網址」或「名稱,網址」格式。回傳成功導入數量。
    func importList(_ text: String) -> Int {
        var count = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }).map(String.init)
            guard let urlPart = parts.last, let url = Self.normalize(urlPart) else { continue }
            let name = parts.dropLast().joined(separator: " ")
            let before = sources.count
            add(name: name, url: url)
            if sources.count > before { count += 1 }
        }
        return count
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
