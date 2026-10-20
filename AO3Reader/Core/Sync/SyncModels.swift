import CryptoKit
import Foundation

/// 個人資料同步的服務商。AO3 帳號資料（書籤、稍後閱讀、閱讀紀錄、訂閱、收件匣）直接讀寫 AO3，不經這裡。
enum SyncProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, iCloud, webDAV

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: String(localized: "關閉")
        case .iCloud: "iCloud"
        case .webDAV: "WebDAV"
        }
    }
}

struct WebDAVConfig: Codable, Equatable, Sendable {
    /// 預設為堅果雲的 WebDAV 位址
    var server = "https://dav.jianguoyun.com/dav/"
    var username = ""
    var folder = "AO3Reader"
}

/// 閱讀進度（章節與段落位置）。
struct ReadingProgress: Codable, Equatable, Sendable {
    var chapter: Int
    var anchor: String?
    var updatedAt: Date

    private static let timePrefix = "reader.progressTime."

    /// 閱讀頁儲存位置時一併記下時間，同步時以較新的進度為準
    static func touch(_ workID: Int) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timePrefix + String(workID))
    }

    static func allLocal() -> [String: ReadingProgress] {
        let defaults = UserDefaults.standard
        var result: [String: ReadingProgress] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(timePrefix) {
            guard let time = value as? Double else { continue }
            let id = String(key.dropFirst(timePrefix.count))
            result[id] = ReadingProgress(
                chapter: defaults.integer(forKey: "reader.position.\(id)"),
                anchor: defaults.string(forKey: "reader.anchor.\(id)"),
                updatedAt: Date(timeIntervalSince1970: time)
            )
        }
        return result
    }

    func apply(workID id: String) {
        let defaults = UserDefaults.standard
        defaults.set(chapter, forKey: "reader.position.\(id)")
        defaults.set(anchor, forKey: "reader.anchor.\(id)")
        defaults.set(updatedAt.timeIntervalSince1970, forKey: Self.timePrefix + id)
    }
}

/// 同步的偏好設定：外觀（不含本機字體與背景圖片）、翻譯設定（不含 API Key）與部分介面選項。
struct SyncedPreferences: Codable, Equatable, Sendable {
    var modifiedAt: Date
    var appearance: AppearanceConfig
    var translation: TranslationConfig
    var options: [String: String]

    /// 以字串保存於 UserDefaults 的介面選項
    static let optionKeys = [
        "account.entryOrder", DownloadFormat.storageKey, StartTab.storageKey,
        "bookshelf.layout", "bookshelf.sort",
    ]

    /// 比較內容是否改變（不含時間）
    var fingerprint: String {
        var copy = self
        copy.modifiedAt = .distantPast
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(copy)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct CoverBlob: Codable, Equatable, Sendable {
    var updatedAt: Date
    var data: Data
}

/// 上傳到 iCloud / WebDAV 的完整資料。每一類資料各自依時間合併，不會互相覆蓋。
struct SyncSnapshot: Codable, Sendable {
    var version = 1
    var updatedAt = Date()
    var bookshelf = BookshelfState()
    var covers: [String: CoverBlob] = [:]
    var reading = ReadingLog()
    var progress: [String: ReadingProgress] = [:]
    var preferences: SyncedPreferences?
    /// 搜尋紀錄（Optional 讓舊的同步檔可正常解碼）
    var searchHistory: SearchHistory?

    static let fileName = "ao3reader-sync.json"
}

enum SyncMerge {
    /// 書架：同一作品取修改時間較新者；移除紀錄比作品新時才移除；手動排序取較新的一份
    static func bookshelf(_ a: BookshelfState, _ b: BookshelfState) -> BookshelfState {
        var items: [Int: BookshelfItem] = [:]
        for item in a.items + b.items {
            if let existing = items[item.id], existing.modifiedAt >= item.modifiedAt { continue }
            items[item.id] = item
        }
        var removed = a.removed.merging(b.removed) { max($0, $1) }
        for (key, date) in removed {
            guard let id = Int(key), let item = items[id] else { continue }
            if date >= item.modifiedAt { items[id] = nil } else { removed[key] = nil }
        }
        let newer = a.orderModifiedAt >= b.orderModifiedAt ? a : b
        var order = newer.manualOrder.filter { items[$0] != nil }
        var seen = Set(order)
        let missing = items.values.sorted { $0.addedAt > $1.addedAt }.map(\.id).filter { seen.insert($0).inserted }
        order = missing + order
        let byOrder = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return BookshelfState(
            items: items.values.sorted { (byOrder[$0.id] ?? 0) < (byOrder[$1.id] ?? 0) },
            removed: removed,
            manualOrder: order,
            orderModifiedAt: max(a.orderModifiedAt, b.orderModifiedAt)
        )
    }

    static func progress(_ a: [String: ReadingProgress], _ b: [String: ReadingProgress]) -> [String: ReadingProgress] {
        a.merging(b) { $0.updatedAt >= $1.updatedAt ? $0 : $1 }
    }
}
