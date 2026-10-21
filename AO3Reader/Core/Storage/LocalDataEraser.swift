// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security
import WebKit

/// 設定 › 隱私 ›「清除所有本地資料」：刪除這台裝置上 App 保存的一切（設定、離線作品、閱讀紀錄、書架、
/// 翻譯快取、匯入的字體、API Key、登入狀態與網頁資料）。不會刪除 iCloud / WebDAV 上的同步資料。
/// 各資料儲存仍在記憶體中，可能在清除後再次寫入，所以清除後由呼叫端關閉 App。
@MainActor
enum LocalDataEraser {
    static func eraseAll() async {
        for itemClass in [kSecClassGenericPassword, kSecClassInternetPassword] {
            SecItemDelete([kSecClass as String: itemClass] as CFDictionary)
        }
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        URLCache.shared.removeAllCachedResponses()
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)

        let manager = FileManager.default
        for directory in [URL.documentsDirectory, URL.applicationSupportDirectory, URL.cachesDirectory, URL.temporaryDirectory] {
            let items = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for item in items { try? manager.removeItem(at: item) }
        }
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
    }
}

/// 批次下載的額度：每 3 天最多 50 部，避免本 App 被用於大量轉載或爬取。
enum BatchDownloadQuota {
    static let limit = 50
    static let window: TimeInterval = 3 * 24 * 60 * 60
    private static let storageKey = "batchDownload.history"

    private static func recent(_ now: Date) -> [Date] {
        let dates = UserDefaults.standard.array(forKey: storageKey) as? [Date] ?? []
        return dates.filter { now.timeIntervalSince($0) < window }
    }

    /// 目前還能批次下載的作品數
    static func remaining(now: Date = Date()) -> Int {
        max(0, limit - recent(now).count)
    }

    /// 額度用完時，下一次恢復額度的時間
    static func nextAvailable(now: Date = Date()) -> Date? {
        guard remaining(now: now) == 0 else { return nil }
        return recent(now).min()?.addingTimeInterval(window)
    }

    static func record(_ count: Int, now: Date = Date()) {
        guard count > 0 else { return }
        let dates = recent(now) + Array(repeating: now, count: count)
        UserDefaults.standard.set(dates, forKey: storageKey)
    }
}
