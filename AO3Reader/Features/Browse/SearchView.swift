import SwiftUI

/// 搜尋分頁：關鍵字 + 官網進階篩選（FilterSheet），結果完全由 AO3 伺服器產生。
struct SearchView: View {
    @Environment(AppState.self) private var app
    @State private var query = WorkSearchQuery()
    @State private var submitted: WorkSearchQuery?
    @State private var model: PagedWorksModel?
    @State private var showsFilters = false

    var body: some View {
        Group {
            if let model, submitted != nil {
                WorkListView(model: model)
            } else {
                ContentUnavailableView(
                    "搜尋 AO3",
                    systemImage: "magnifyingglass",
                    description: Text("輸入關鍵字，或點右上角使用官網的進階篩選")
                )
            }
        }
        .navigationTitle("搜尋")
        .searchable(text: $query.query, prompt: "標題、作者、標籤、關鍵字")
        .onSubmit(of: .search) { submit() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsFilters = true
                } label: {
                    Label("篩選", systemImage: query.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(query: $query) {
                showsFilters = false
                submit()
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func submit() {
        let snapshot = query
        let client = app.client
        submitted = snapshot
        let loader: PagedWorksModel.Loader = { page in try await client.searchWorks(snapshot, page: page) }
        let model = PagedWorksModel(loader: loader)
        self.model = model
        Task { await model.reload() }
    }
}
