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
                    Button("篩選", systemImage: "line.3.horizontal.decrease") { showsFilters = true }
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

    private func load() async {
        let client = app.client
        let route = route
        let query = route.filterable ? route.baseQuery + filter.filterItems(page: 1) : route.baseQuery
        let model = PagedWorksModel { page in
            try await client.worksPage(path: route.path, query: query, page: page)
        }
        self.model = model
        await model.reload()
    }
}
