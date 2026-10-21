// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftSoup

extension AO3Parser {
    /// 訂閱目標的內容指紋：作品為章節數與更新日期，系列為統計列，作者為最新一部作品。
    static func subscriptionFingerprint(html: String, kind: LocalSubscription.Kind) throws -> String? {
        let doc = try SwiftSoup.parse(html)
        switch kind {
        case .work:
            let chapters = try doc.select("dl.stats dd.chapters").first()?.text() ?? ""
            let updated = try doc.select("dl.stats dd.status").first()?.text()
                ?? doc.select("dl.stats dd.published").first()?.text() ?? ""
            return chapters.isEmpty && updated.isEmpty ? nil : "\(chapters)|\(updated)"
        case .series:
            let stats = try doc.select("dl.series dl.stats, dl.series.meta dl.stats, dl.stats").first()?.text() ?? ""
            return stats.isEmpty ? nil : stats
        case .user:
            return try doc.select("li.work.blurb, li.blurb.work").first()?.attr("id")
        }
    }
}

extension AO3Client {
    func subscriptionFingerprint(_ subscription: LocalSubscription) async throws -> String? {
        if isDemo { return nil }
        var path = subscription.path
        var query: [URLQueryItem] = []
        switch subscription.kind {
        case .work: query = [URLQueryItem(name: "view_adult", value: "true")]
        case .series: break
        case .user: path += "/works"
        }
        let html = try await get(path, query: query)
        return try AO3Parser.subscriptionFingerprint(html: html, kind: subscription.kind)
    }
}

extension AppState {
    /// 本機訂閱的更新檢查：App 開啟或回到前景時執行。每項至少間隔 6 小時，每次最多 20 項，
    /// 請求之間稍作間隔，避免對 AO3 造成負擔。
    func checkLocalSubscriptions(force: Bool = false) async {
        guard DataSource.current == .local else { return }
        let due = library.library.subscriptions
            .filter { force || ($0.lastCheckedAt ?? .distantPast) < Date().addingTimeInterval(-6 * 3600) }
            .prefix(force ? 50 : 20)
        let client = client
        for subscription in due {
            if let fingerprint = try? await client.subscriptionFingerprint(subscription) {
                library.updateSubscription(subscription.path, fingerprint: fingerprint)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// 從 AO3 帳號匯入書籤、稍後閱讀、閱讀紀錄與訂閱到本機（只新增，不覆蓋）。
    /// 每類最多讀取 `pageLimit` 頁，回報目前進度。
    func importFromAO3(pageLimit: Int = 20, progress: @escaping @MainActor (String) -> Void) async throws {
        guard let username = auth.username else { throw AO3Error.requiresLogin }
        let client = client

        func collect(_ kind: UserListKind) async throws -> [WorkSummary] {
            var works: [WorkSummary] = []
            var page = 1
            while page <= pageLimit {
                progress(String(localized: "正在讀取\(kind.title)（第 \(page) 頁）"))
                let result = try await client.userList(kind, username: username, page: page)
                works += result.works
                guard result.hasNextPage else { break }
                page += 1
                try await Task.sleep(for: .seconds(1))
            }
            return works
        }

        let bookmarks = try await collect(.bookmarks)
        let later = try await collect(.markedForLater)
        let history = try await collect(.history)

        var subscriptions: [LocalSubscription] = []
        let now = Date()
        for kind in SubscriptionItem.Kind.allCases {
            var page = 1
            while page <= pageLimit {
                progress(String(localized: "正在讀取訂閱（第 \(page) 頁）"))
                let result = try await client.subscriptions(username: username, kind: kind, page: page)
                for item in result.items {
                    let localKind: LocalSubscription.Kind = switch kind {
                    case .works: .work
                    case .series: .series
                    case .users: .user
                    }
                    subscriptions.append(LocalSubscription(kind: localKind, path: item.path, name: item.title,
                                                           createdAt: now, modifiedAt: now))
                }
                guard result.hasNextPage else { break }
                page += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
        library.importFromAO3(bookmarks: bookmarks, later: later, history: history, subscriptions: subscriptions)
    }
}
