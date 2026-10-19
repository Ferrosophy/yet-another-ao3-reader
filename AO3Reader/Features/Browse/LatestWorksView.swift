import SwiftUI

/// 首頁：以官網搜尋（依更新日期排序）列出最新作品，可依語言快速篩選。
struct LatestWorksView: View {
    @Environment(AppState.self) private var app
    @AppStorage("latest.languageID") private var languageID = ""
    @State private var model: PagedWorksModel?

    private static let languages: [(String, String)] = [
        ("", "全部語言"), ("en", "English"), ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"),
        ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("ru", "Русский"),
    ]

    var body: some View {
        Group {
            if let model { WorkListView(model: model) } else { ProgressView() }
        }
        .navigationTitle("最新作品")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("語言", selection: $languageID) {
                        ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } label: {
                    Label("語言", systemImage: "globe")
                }
            }
        }
        .task(id: languageID) {
            let client = app.client
            var query = WorkSearchQuery()
            query.sortColumn = .dateUpdated
            query.languageID = languageID
            let snapshot = query
            let loader: PagedWorksModel.Loader = { page in try await client.searchWorks(snapshot, page: page) }
            if let model {
                model.replaceLoader(loader)
            } else {
                model = PagedWorksModel(loader: loader)
            }
            await model?.reload()
        }
    }
}
