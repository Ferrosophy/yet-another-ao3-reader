import Foundation
import Observation

/// 使用者資料的來源：AO3 帳號，或本機保存。兩者只能擇一，切換時不合併也不刪除。
enum DataSource: String, CaseIterable, Identifiable, Sendable {
    case ao3, local

    var id: String { rawValue }
    var title: String { self == .ao3 ? String(localized: "AO3 帳號") : String(localized: "本機保存") }

    static let storageKey = "data.source"
    static var current: DataSource {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DataSource.init) ?? .ao3
    }
}

/// 本機書籤（與 AO3 書籤欄位相同：備註、自訂標籤、私人）。
struct LocalBookmark: Codable, Identifiable, Hashable, Sendable {
    var work: WorkSummary
    var notes = ""
    var tags = ""
    var isPrivate = false
    var createdAt: Date
    var modifiedAt: Date
    var id: Int { work.id }
}

/// 稍後閱讀、閱讀紀錄共用的作品條目。
struct LocalWorkEntry: Codable, Identifiable, Hashable, Sendable {
    var work: WorkSummary
    /// 加入時間（稍後閱讀）或最後閱讀時間（閱讀紀錄）
    var date: Date
    var visits = 1
    var modifiedAt: Date
    var id: Int { work.id }
}

/// 本機訂閱：作品、系列或作者。更新由 App 開啟或回到前景時檢查。
struct LocalSubscription: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case work, series, user }

    var kind: Kind
    /// 作品為 /works/<id>，系列為 /series/<id>，作者為 /users/<name>
    var path: String
    var name: String
    /// 上次檢查時的內容指紋（章節數、更新日期或最新作品），改變即代表有更新
    var fingerprint: String?
    var hasUpdate = false
    var lastCheckedAt: Date?
    var createdAt: Date
    var modifiedAt: Date
    var id: String { path }
}

/// 本機使用者資料（可經 iCloud / WebDAV 同步）。每一類各自保存移除紀錄，同步時以修改時間合併。
struct LocalLibrary: Codable, Equatable, Sendable {
    var bookmarks: [LocalBookmark] = []
    var later: [LocalWorkEntry] = []
    var history: [LocalWorkEntry] = []
    var subscriptions: [LocalSubscription] = []
    /// 移除紀錄：類別前綴 + ID（b:123、l:123、h:123、s:/series/1）→ 移除時間
    var removed: [String: Date] = [:]

    static let fileName = "yaao3r-library.json"
    /// 閱讀紀錄最多保留筆數（AO3 帳號的閱讀紀錄也只顯示最近這麼多部）
    static let historyLimit = 100

    func merged(with other: LocalLibrary) -> LocalLibrary {
        let removed = self.removed.merging(other.removed) { max($0, $1) }
        func merge<T: Identifiable>(_ a: [T], _ b: [T], prefix: String, modified: (T) -> Date, key: (T) -> String) -> [T] {
            var result: [String: T] = [:]
            for item in a + b {
                let k = key(item)
                if let existing = result[k], modified(existing) >= modified(item) { continue }
                result[k] = item
            }
            return result.filter { k, item in
                guard let date = removed["\(prefix):\(k)"] else { return true }
                return modified(item) > date
            }.map(\.value)
        }
        var result = LocalLibrary(removed: removed)
        result.bookmarks = merge(bookmarks, other.bookmarks, prefix: "b", modified: \.modifiedAt, key: { String($0.id) })
            .sorted { $0.createdAt > $1.createdAt }
        result.later = merge(later, other.later, prefix: "l", modified: \.modifiedAt, key: { String($0.id) })
            .sorted { $0.date > $1.date }
        result.history = Array(merge(history, other.history, prefix: "h", modified: \.modifiedAt, key: { String($0.id) })
            .sorted { $0.date > $1.date }.prefix(Self.historyLimit))
        result.subscriptions = merge(subscriptions, other.subscriptions, prefix: "s", modified: \.modifiedAt, key: \.path)
            .sorted { $0.createdAt > $1.createdAt }
        return result
    }
}

/// 本機保存的書籤、稍後閱讀、閱讀紀錄與訂閱（資料來源選「本機保存」時使用）。
@MainActor
@Observable
final class LocalLibraryStore {
    private(set) var library: LocalLibrary

    private static let url = URL.applicationSupportDirectory.appending(path: LocalLibrary.fileName)

    init() {
        library = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder().decode(LocalLibrary.self, from: $0) }
            ?? LocalLibrary()
    }

    // MARK: 書籤

    func bookmark(_ id: Int) -> LocalBookmark? { library.bookmarks.first { $0.id == id } }

    func saveBookmark(_ work: WorkSummary, notes: String, tags: String, isPrivate: Bool) {
        let now = Date()
        if let index = library.bookmarks.firstIndex(where: { $0.id == work.id }) {
            library.bookmarks[index].work = work
            library.bookmarks[index].notes = notes
            library.bookmarks[index].tags = tags
            library.bookmarks[index].isPrivate = isPrivate
            library.bookmarks[index].modifiedAt = now
        } else {
            library.bookmarks.insert(LocalBookmark(work: work, notes: notes, tags: tags, isPrivate: isPrivate,
                                                   createdAt: now, modifiedAt: now), at: 0)
        }
        library.removed["b:\(work.id)"] = nil
        save()
    }

    func removeBookmark(_ id: Int) {
        library.bookmarks.removeAll { $0.id == id }
        library.removed["b:\(id)"] = Date()
        save()
    }

    // MARK: 稍後閱讀

    func isMarkedForLater(_ id: Int) -> Bool { library.later.contains { $0.id == id } }

    func toggleLater(_ work: WorkSummary) {
        if isMarkedForLater(work.id) {
            library.later.removeAll { $0.id == work.id }
            library.removed["l:\(work.id)"] = Date()
        } else {
            let now = Date()
            library.later.insert(LocalWorkEntry(work: work, date: now, modifiedAt: now), at: 0)
            library.removed["l:\(work.id)"] = nil
        }
        save()
    }

    // MARK: 閱讀紀錄

    func recordVisit(_ work: WorkSummary) {
        let now = Date()
        var entry = library.history.first { $0.id == work.id } ?? LocalWorkEntry(work: work, date: now, visits: 0, modifiedAt: now)
        entry.work = work
        entry.date = now
        entry.visits += 1
        entry.modifiedAt = now
        library.history.removeAll { $0.id == work.id }
        library.history.insert(entry, at: 0)
        if library.history.count > LocalLibrary.historyLimit { library.history.removeLast(library.history.count - LocalLibrary.historyLimit) }
        library.removed["h:\(work.id)"] = nil
        save()
    }

    func removeHistory(_ id: Int) {
        library.history.removeAll { $0.id == id }
        library.removed["h:\(id)"] = Date()
        save()
    }

    // MARK: 訂閱

    func subscription(_ path: String) -> LocalSubscription? { library.subscriptions.first { $0.path == path } }

    func toggleSubscription(kind: LocalSubscription.Kind, path: String, name: String) {
        if subscription(path) != nil {
            library.subscriptions.removeAll { $0.path == path }
            library.removed["s:\(path)"] = Date()
        } else {
            let now = Date()
            library.subscriptions.insert(LocalSubscription(kind: kind, path: path, name: name, createdAt: now, modifiedAt: now), at: 0)
            library.removed["s:\(path)"] = nil
        }
        save()
    }

    /// 更新檢查結果：指紋改變時標記為有更新（第一次檢查只記下指紋）
    func updateSubscription(_ path: String, fingerprint: String) {
        guard let index = library.subscriptions.firstIndex(where: { $0.path == path }) else { return }
        var item = library.subscriptions[index]
        if let old = item.fingerprint, old != fingerprint { item.hasUpdate = true }
        item.fingerprint = fingerprint
        item.lastCheckedAt = Date()
        item.modifiedAt = Date()
        library.subscriptions[index] = item
        save()
    }

    func markSubscriptionSeen(_ path: String) {
        guard let index = library.subscriptions.firstIndex(where: { $0.path == path }), library.subscriptions[index].hasUpdate else { return }
        library.subscriptions[index].hasUpdate = false
        library.subscriptions[index].modifiedAt = Date()
        save()
    }

    // MARK: 匯入與同步

    /// 從 AO3 匯入：只新增本機沒有的項目，不覆蓋本機已有的資料
    func importFromAO3(bookmarks: [WorkSummary], later: [WorkSummary], history: [WorkSummary],
                       subscriptions: [LocalSubscription]) {
        let now = Date()
        for work in bookmarks where bookmark(work.id) == nil {
            library.bookmarks.append(LocalBookmark(work: work, createdAt: now, modifiedAt: now))
        }
        for work in later where !isMarkedForLater(work.id) {
            library.later.append(LocalWorkEntry(work: work, date: now, modifiedAt: now))
        }
        for work in history where !library.history.contains(where: { $0.id == work.id }) {
            library.history.append(LocalWorkEntry(work: work, date: now, modifiedAt: now))
        }
        for item in subscriptions where subscription(item.path) == nil {
            library.subscriptions.append(item)
        }
        save()
    }

    func apply(_ merged: LocalLibrary) {
        guard merged != library else { return }
        library = merged
        save(notify: false)
    }

    private func save(notify: Bool = true) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(library).write(to: Self.url, options: .atomic)
        if notify { NotificationCenter.default.post(name: .localLibraryChanged, object: nil) }
    }
}

extension Notification.Name {
    /// 本機使用者資料有變更，供本機資料同步排程上傳
    static let localLibraryChanged = Notification.Name("LocalLibraryChanged")
}
