// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// 通用的分頁作品列表：搜尋結果、最新作品、閱讀紀錄、書籤都用它。
@MainActor
@Observable
final class PagedWorksModel {
    typealias Loader = @Sendable (_ page: Int) async throws -> WorkPage

    private(set) var works: [WorkSummary] = []
    private(set) var heading: String?
    private(set) var isLoading = false
    private(set) var hasNextPage = false
    private(set) var hasLoaded = false
    var error: String?

    private var page = 0
    /// 每次重新載入遞增，用來丟棄過期的請求結果
    private var generation = 0
    private var loader: Loader

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    /// 第一頁的請求被取消、還沒有結果：畫面再次出現時應重新載入
    var needsReload: Bool { !hasLoaded && !isLoading && works.isEmpty && error == nil }

    func replaceLoader(_ loader: @escaping Loader) {
        self.loader = loader
    }

    /// 重新載入第一頁。`clear` 為 true 時（篩選條件改變）立即清空舊結果並顯示載入中；
    /// 進行中的舊請求結果會被丟棄，不會擋住或覆蓋這次載入。
    func reload(clear: Bool = false) async {
        generation += 1
        page = 0
        hasNextPage = false
        isLoading = false
        if clear {
            works = []
            heading = nil
            error = nil
            hasLoaded = false
        }
        await loadNext(reset: true)
    }

    /// 快速跳轉：載入到至少 `count` 部作品或沒有下一頁為止。每次最多 10 頁，頁與頁之間稍作間隔，避免對 AO3 造成負擔
    func loadUntil(count: Int) async {
        var pages = 0
        while works.count < count, hasNextPage, pages < 10 {
            let before = works.count
            await loadNext(reset: false)
            pages += 1
            if works.count == before { break }
            if works.count < count, hasNextPage { try? await Task.sleep(for: .milliseconds(600)) }
        }
    }

    func loadMoreIfNeeded(current work: WorkSummary) async {
        guard hasNextPage, !isLoading, work.id == works.last?.id else { return }
        await loadNext(reset: false)
    }

    private func loadNext(reset: Bool) async {
        guard !isLoading else { return }
        let generation = generation
        var cancelled = false
        isLoading = true
        defer {
            if generation == self.generation {
                isLoading = false
                hasLoaded = !cancelled
            }
        }
        do {
            // 請求不跟著畫面的 task 取消：切換分頁、進出作品頁或切換來源時畫面會暫時消失，
            // 若請求被取消會留下「載入失敗」，回到畫面時條件沒變也不會重新載入
            let loader = loader
            let next = page + 1
            let result = try await Task { try await loader(next) }.value
            guard generation == self.generation else { return }
            page = result.page
            hasNextPage = result.hasNextPage
            heading = result.heading
            // 列表跨頁時可能重複（作品更新排序變動），以 id 去重
            let existing = reset ? [] : Set(works.map(\.id))
            let fresh = result.works.filter { !existing.contains($0.id) }
            works = reset ? fresh : works + fresh
            error = nil
        } catch {
            guard generation == self.generation else { return }
            // 被取消的請求不算失敗：保持未載入狀態，下次出現時重新載入
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                cancelled = true
                return
            }
            self.error = error.localizedDescription
        }
    }
}
