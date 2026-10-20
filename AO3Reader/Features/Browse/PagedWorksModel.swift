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

    func loadMoreIfNeeded(current work: WorkSummary) async {
        guard hasNextPage, !isLoading, work.id == works.last?.id else { return }
        await loadNext(reset: false)
    }

    private func loadNext(reset: Bool) async {
        guard !isLoading else { return }
        let generation = generation
        isLoading = true
        defer {
            if generation == self.generation {
                isLoading = false
                hasLoaded = true
            }
        }
        do {
            let result = try await loader(page + 1)
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
            self.error = error.localizedDescription
        }
    }
}
