import Foundation
import Observation
import UIKit

/// 書架上的一部作品（本機資料，可經 iCloud / WebDAV 同步，與 AO3 帳號資料分開）。
struct BookshelfItem: Codable, Identifiable, Hashable, Sendable {
    var work: WorkSummary
    var addedAt: Date
    var lastReadAt: Date?
    /// 自訂封面最後修改時間；nil 為使用預設封面
    var coverUpdatedAt: Date?
    /// 任何欄位修改的時間，同步合併時以較新者為準
    var modifiedAt: Date

    var id: Int { work.id }
}

enum BookshelfSort: String, CaseIterable, Codable, Identifiable, Sendable {
    case manual, recentlyRead, added, title, author

    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: String(localized: "手動排序")
        case .recentlyRead: String(localized: "最近閱讀")
        case .added: String(localized: "加入時間")
        case .title: String(localized: "標題")
        case .author: String(localized: "作者")
        }
    }
}

enum BookshelfLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case list, grid
    var id: String { rawValue }
    /// list 顯示為左右滑動的卡片（沿用舊的儲存值）
    var title: String { self == .list ? String(localized: "卡片") : String(localized: "網格") }
    var systemImage: String { self == .list ? "rectangle.stack" : "square.grid.2x2" }
}

/// 書架的可同步狀態
struct BookshelfState: Codable, Equatable, Sendable {
    var items: [BookshelfItem] = []
    /// 已移除作品的移除時間，避免同步時被其他裝置加回
    var removed: [String: Date] = [:]
    /// 手動排序（作品 ID）
    var manualOrder: [Int] = []
    var orderModifiedAt = Date.distantPast
}

@MainActor
@Observable
final class BookshelfStore {
    private(set) var state: BookshelfState
    /// 自訂封面快取
    private(set) var covers: [Int: UIImage] = [:]

    var items: [BookshelfItem] { state.items }

    private static let directory = URL.applicationSupportDirectory.appending(path: "Bookshelf", directoryHint: .isDirectory)
    private static let stateURL = directory.appending(path: "bookshelf.json")
    static func coverURL(_ id: Int) -> URL { directory.appending(path: "cover-\(id).jpg") }

    init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        state = (try? Data(contentsOf: Self.stateURL)).flatMap { try? JSONDecoder().decode(BookshelfState.self, from: $0) }
            ?? BookshelfState()
        for item in state.items where item.coverUpdatedAt != nil {
            if let data = try? Data(contentsOf: Self.coverURL(item.id)) { covers[item.id] = UIImage(data: data) }
        }
    }

    func contains(_ id: Int) -> Bool { state.items.contains { $0.id == id } }

    func add(_ work: WorkSummary) {
        let now = Date()
        if let index = state.items.firstIndex(where: { $0.id == work.id }) {
            state.items[index].work = work
            state.items[index].modifiedAt = now
        } else {
            state.items.append(BookshelfItem(work: work, addedAt: now, modifiedAt: now))
            state.manualOrder.insert(work.id, at: 0)
            state.orderModifiedAt = now
            state.removed[String(work.id)] = nil
        }
        save()
    }

    func remove(_ id: Int) {
        state.items.removeAll { $0.id == id }
        state.manualOrder.removeAll { $0 == id }
        state.removed[String(id)] = Date()
        state.orderModifiedAt = Date()
        covers[id] = nil
        try? FileManager.default.removeItem(at: Self.coverURL(id))
        save()
    }

    func toggle(_ work: WorkSummary) {
        if contains(work.id) { remove(work.id) } else { add(work) }
    }

    /// 開啟閱讀時更新最近閱讀時間（只對書架上的作品）
    func markRead(_ id: Int, info: WorkSummary? = nil) {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        state.items[index].lastReadAt = now
        if let info { state.items[index].work = info }
        state.items[index].modifiedAt = now
        save()
    }

    func sorted(by sort: BookshelfSort, ascending: Bool) -> [BookshelfItem] {
        let items = state.items
        switch sort {
        case .manual:
            let position = Dictionary(state.manualOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            return items.sorted { (position[$0.id] ?? .max, $1.addedAt) < (position[$1.id] ?? .max, $0.addedAt) }
        case .recentlyRead:
            let result = items.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
            return ascending ? result.reversed() : result
        case .added:
            let result = items.sorted { $0.addedAt > $1.addedAt }
            return ascending ? result.reversed() : result
        case .title:
            let result = items.sorted { $0.work.title.localizedStandardCompare($1.work.title) == .orderedAscending }
            return ascending ? result : result.reversed()
        case .author:
            let result = items.sorted {
                ($0.work.authors.first ?? "").localizedStandardCompare($1.work.authors.first ?? "") == .orderedAscending
            }
            return ascending ? result : result.reversed()
        }
    }

    /// 手動排序：以目前的手動順序移動
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = sorted(by: .manual, ascending: true).map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        state.manualOrder = order
        state.orderModifiedAt = Date()
        save()
    }

    // MARK: 封面

    func setCover(_ data: Data, for id: Int) throws {
        guard let image = UIImage(data: data), let index = state.items.firstIndex(where: { $0.id == id }) else {
            throw AppearanceError.invalidImage
        }
        let scaled = image.preparingThumbnail(of: Self.thumbnailSize(for: image.size)) ?? image
        guard let jpeg = scaled.jpegData(compressionQuality: 0.8) else { throw AppearanceError.invalidImage }
        try jpeg.write(to: Self.coverURL(id), options: .atomic)
        covers[id] = scaled
        let now = Date()
        state.items[index].coverUpdatedAt = now
        state.items[index].modifiedAt = now
        save()
    }

    func removeCover(for id: Int) {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        covers[id] = nil
        try? FileManager.default.removeItem(at: Self.coverURL(id))
        state.items[index].coverUpdatedAt = nil
        state.items[index].modifiedAt = Date()
        save()
    }

    private static func thumbnailSize(for size: CGSize) -> CGSize {
        let maxSide: CGFloat = 900
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: 同步

    /// 合併遠端狀態（以每部作品的修改時間為準），並寫入需要的封面
    func apply(_ merged: BookshelfState, covers remoteCovers: [Int: Data]) {
        for (id, data) in remoteCovers {
            try? data.write(to: Self.coverURL(id), options: .atomic)
            covers[id] = UIImage(data: data)
        }
        for id in covers.keys where !merged.items.contains(where: { $0.id == id && $0.coverUpdatedAt != nil }) {
            covers[id] = nil
            try? FileManager.default.removeItem(at: Self.coverURL(id))
        }
        state = merged
        save()
    }

    func coverData(_ id: Int) -> Data? { try? Data(contentsOf: Self.coverURL(id)) }

    private func save() {
        try? JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
        NotificationCenter.default.post(name: .personalDataChanged, object: nil)
    }
}

extension Notification.Name {
    /// 書架、閱讀時長等個人資料有變更，供同步服務排程上傳
    static let personalDataChanged = Notification.Name("PersonalDataChanged")
}
