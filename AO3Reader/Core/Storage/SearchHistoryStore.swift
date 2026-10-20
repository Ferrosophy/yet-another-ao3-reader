import Foundation
import Observation

/// 搜尋紀錄（每個搜尋範圍各自保留最近 10 筆），隨「離線清單同步」與閱讀時長一起同步。
struct SearchHistory: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// 搜尋範圍（works、tags、people、collections）
        var scope: String
        var term: String
        var date: Date
        var key: String { "\(scope):\(term.lowercased())" }
    }

    var entries: [Entry] = []
    /// 刪除紀錄：key → 刪除時間，避免同步時被其他裝置加回
    var removed: [String: Date] = [:]

    static let limit = 10

    func merged(with other: SearchHistory) -> SearchHistory {
        let removed = self.removed.merging(other.removed) { max($0, $1) }
        var latest: [String: Entry] = [:]
        for entry in entries + other.entries {
            if let existing = latest[entry.key], existing.date >= entry.date { continue }
            latest[entry.key] = entry
        }
        let kept = latest.values.filter { entry in
            guard let date = removed[entry.key] else { return true }
            return entry.date > date
        }
        var result = SearchHistory(removed: removed)
        // 每個範圍只留最近 10 筆
        for scope in Set(kept.map(\.scope)) {
            result.entries += kept.filter { $0.scope == scope }.sorted { $0.date > $1.date }.prefix(Self.limit)
        }
        result.entries.sort { $0.date > $1.date }
        return result
    }
}

@MainActor
@Observable
final class SearchHistoryStore {
    private(set) var history: SearchHistory

    private static let url = URL.applicationSupportDirectory.appending(path: "search-history.json")

    init() {
        history = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder().decode(SearchHistory.self, from: $0) }
            ?? SearchHistory()
    }

    func terms(for scope: String) -> [String] {
        history.entries.filter { $0.scope == scope }.sorted { $0.date > $1.date }.map(\.term)
    }

    func add(_ term: String, scope: String) {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        let entry = SearchHistory.Entry(scope: scope, term: term, date: Date())
        history.entries.removeAll { $0.key == entry.key }
        history.entries.insert(entry, at: 0)
        history.removed[entry.key] = nil
        let scoped = history.entries.filter { $0.scope == scope }
        if scoped.count > SearchHistory.limit {
            let dropped = Set(scoped.dropFirst(SearchHistory.limit).map(\.key))
            history.entries.removeAll { dropped.contains($0.key) }
        }
        save()
    }

    func remove(_ term: String, scope: String) {
        let key = SearchHistory.Entry(scope: scope, term: term, date: Date()).key
        history.entries.removeAll { $0.key == key }
        history.removed[key] = Date()
        save()
    }

    func clear(scope: String) {
        for entry in history.entries where entry.scope == scope { history.removed[entry.key] = Date() }
        history.entries.removeAll { $0.scope == scope }
        save()
    }

    /// 同步：套用合併後的紀錄
    func apply(_ merged: SearchHistory) {
        guard merged != history else { return }
        history = merged
        save(notify: false)
    }

    private func save(notify: Bool = true) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(history).write(to: Self.url, options: .atomic)
        if notify { NotificationCenter.default.post(name: .personalDataChanged, object: nil) }
    }
}
