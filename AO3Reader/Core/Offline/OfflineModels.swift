// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

/// 離線保存的作品內容（閱讀用副本）：原文段落、作者註、標籤與作品資訊，與線上載入的 `WorkDetail` 互轉。
struct OfflineWork: Codable, Sendable {
    var id: Int
    var title: String
    var authors: [String]
    var summary: String
    var notes: String
    var endNotes: String
    var chapters: [Chapter]
    var tagGroups: [WorkTagGroup]
    var series: [WorkTag]
    var authorLinks: [WorkTag]
    var info: WorkSummary?
    var downloadedAt: Date

    init(detail: WorkDetail, downloadedAt: Date = Date()) {
        id = detail.id
        title = detail.title
        authors = detail.authors
        summary = detail.summary
        notes = detail.notes
        endNotes = detail.endNotes
        chapters = detail.chapters
        tagGroups = detail.tagGroups
        series = detail.series
        authorLinks = detail.authorLinks
        info = detail.info
        self.downloadedAt = downloadedAt
    }

    var detail: WorkDetail {
        WorkDetail(id: id, title: title, authors: authors, summary: summary, chapters: chapters,
                   notes: notes, endNotes: endNotes, tagGroups: tagGroups, series: series,
                   authorLinks: authorLinks, actions: nil, downloads: [:], info: info)
    }

    /// 所有需要翻譯的段落：作品與章節的標題、簡介、作者註，以及正文
    var translatableParagraphs: [Paragraph] {
        let detail = detail
        var result: [Paragraph] = []
        for index in chapters.indices {
            result += ReaderViewModel.metaParagraphs(detail: detail, chapters: [index], includeAll: true)
            result += chapters[index].paragraphs.filter(\.isTranslatable)
        }
        return result
    }
}

/// 離線譯文：以段落 ID 對應，附原文雜湊；原文改變（作者修訂）時該段視為未翻譯。
struct OfflineTranslations: Codable, Sendable {
    struct Entry: Codable, Sendable {
        var hash: String
        var text: String
    }

    var targetLanguageCode: String
    var entries: [String: Entry] = [:]

    func text(for paragraph: Paragraph) -> String? {
        guard let entry = entries[paragraph.id], entry.hash == Self.hash(paragraph.text) else { return nil }
        return entry.text
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// 書架作品的離線狀態（只存在這台裝置，不同步）。
struct OfflineRecord: Codable, Sendable {
    var chapterCount = 0
    var downloadedAt: Date?
    /// 譯文的目標語言；nil 為尚未翻譯
    var translatedLanguage: String?
    /// 已翻譯段落數 / 需翻譯段落數
    var translatedCount = 0
    var translatableCount = 0
    /// 匯出檔的格式與檔名（位於 Documents/Bookshelf，可在「檔案」App 中看到）
    var format: DownloadFormat?
    var exportFileName: String?
    /// 上次檢查新章節的時間
    var lastCheckedAt: Date?
    /// 有新章節可下載
    var hasUpdate = false
    /// 匯出檔對應的章節數（官網格式只在章節變化時重新下載）
    var exportedChapterCount: Int?
    /// 使用者刪除了離線內容（保留書架項目，不再自動下載）
    var contentDeleted = false
    /// 作品的原文語言（AO3 顯示名稱，例如 English）；與目標語言相同時不翻譯
    var originalLanguage: String?

    var isTranslationComplete: Bool { translatableCount > 0 && translatedCount >= translatableCount }
}

/// 處理中的狀態（不保存）。
enum OfflineActivity: Equatable, Sendable {
    case queued
    case downloading
    /// 分章下載（斷點續傳）中：已完成章數 / 總章數
    case downloadingChapters(done: Int, total: Int)
    case translating(done: Int, total: Int)
    case exporting
    case paused
    /// 等待 Wi-Fi（設定為僅在 Wi-Fi 下下載時）
    case waitingForWiFi
    /// 使用付費翻譯 API，等待使用者同意
    case awaitingConsent
    case failed(String)

    /// 排隊或處理中
    var isActive: Bool {
        switch self {
        case .queued, .downloading, .downloadingChapters, .translating, .exporting: true
        default: false
        }
    }
}

/// 分章下載的進度（斷點續傳）：已下載的章節存在作品資料夾，失敗或中斷後從下一章繼續。
struct OfflinePartial: Codable, Sendable {
    var chapterIDs: [Int]
    /// 已下載的部分（作品資訊取自第一章頁面）
    var work: OfflineWork?

    var downloadedCount: Int { work?.chapters.count ?? 0 }
}
