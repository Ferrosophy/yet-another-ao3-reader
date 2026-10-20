import SwiftUI

/// 標籤 / 合集 / 系列 / 用戶的作品列表。可篩選的列表使用官網「Sort and Filter」參數，
/// 例如先進入某標籤，再加入其他標籤、排除標籤、分級等條件。
struct WorkListScreen: View {
    let route: WorkListRoute
    @Environment(AppState.self) private var app
    @State private var filter = WorkSearchQuery(sortColumn: .dateUpdated)
    @State private var model: PagedWorksModel?
    @State private var showsFilters = false

    var body: some View {
        Group {
            if let model { WorkListView(model: model) } else { AO3LoadingView() }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if route.filterable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("詳細篩選", systemImage: filter == Self.defaultFilter ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") { showsFilters = true }
                }
            }
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(query: $filter, mode: .filter) {
                showsFilters = false
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            guard model == nil else { return }
            await load()
        }
    }

    private static let defaultFilter = WorkSearchQuery(sortColumn: .dateUpdated)

    /// 有篩選條件時先使用官網的「Sort and Filter」；頁面沒有篩選表單（未整理的小標籤、系列、
    /// 部分用戶頁）時官網會忽略篩選參數，改為讀取全部作品後在本機篩選與排序。
    private func load() async {
        let client = app.client
        let route = route
        let filter = filter
        let model: PagedWorksModel
        if route.filterable, filter != Self.defaultFilter {
            let query = route.baseQuery + filter.filterItems(page: 1)
            let first = try? await client.worksPage(path: route.path, query: query, page: 1)
            if first?.filterable == false {
                model = PagedWorksModel { _ in
                    try await Self.filterLocally(client: client, route: route, filter: filter)
                }
            } else {
                model = PagedWorksModel { page in
                    try await client.worksPage(path: route.path, query: query, page: page)
                }
            }
        } else {
            model = PagedWorksModel { page in
                try await client.worksPage(path: route.path, query: route.baseQuery, page: page)
            }
        }
        self.model = model
        await model.reload()
    }

    /// 讀取未篩選的作品（最多 10 頁），在本機套用篩選條件並排序
    private static func filterLocally(client: AO3Client, route: WorkListRoute, filter: WorkSearchQuery) async throws -> WorkPage {
        var works: [WorkSummary] = []
        var page = 1
        while page <= 10 {
            let result = try await client.worksPage(path: route.path, query: route.baseQuery, page: page)
            works += result.works
            guard result.hasNextPage else { break }
            page += 1
            try await Task.sleep(for: .milliseconds(500))
        }
        let languages = Dictionary(LatestWorksView.cachedLanguages().map { ($0.name, $0.code) }, uniquingKeysWith: { first, _ in first })
        let matched = works.filter { filter.matches($0, languageCodes: languages) }
        return WorkPage(works: filter.sorted(matched), page: 1, hasNextPage: false)
    }
}
