import Observation
import SwiftUI

/// 通用分頁列表（標籤、用戶、合集、訂閱、收件匣）。作品列表另用 `PagedWorksModel`（含標題資訊）。
@MainActor
@Observable
final class PagedListModel<Item: Identifiable & Sendable> {
    typealias Loader = @Sendable (_ page: Int) async throws -> ListPage<Item>

    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var hasNextPage = false
    private(set) var hasLoaded = false
    var error: String?

    private var page = 0
    private let loader: Loader

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func reload() async {
        page = 0
        hasNextPage = false
        await loadNext(reset: true)
    }

    func loadMoreIfNeeded(current item: Item) async {
        guard hasNextPage, !isLoading, item.id == items.last?.id else { return }
        await loadNext(reset: false)
    }

    private func loadNext(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let result = try await loader(page + 1)
            page = result.page
            hasNextPage = result.hasNextPage
            let existing = reset ? [] : Set(items.map(\.id))
            let fresh = result.items.filter { !existing.contains($0.id) }
            items = reset ? fresh : items + fresh
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PagedListView<Item: Identifiable & Sendable, Row: View>: View {
    let model: PagedListModel<Item>
    var emptyTitle: LocalizedStringKey = "沒有結果"
    var header: AnyView?
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        List {
            if let header {
                header
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(model.items) { item in
                    row(item)
                        .task { await model.loadMoreIfNeeded(current: item) }
                }
            }
            .listSectionSeparator(.hidden)
            if model.isLoading, !model.items.isEmpty {
                AO3LoadingView(compact: true)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .overlay {
            if let error = model.error, model.items.isEmpty {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重試") { Task { await model.reload() } }
                        .buttonStyle(.glassProminent)
                }
            } else if model.isLoading, model.items.isEmpty {
                AO3LoadingView()
            } else if model.hasLoaded, !model.isLoading, model.items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "tray")
            }
        }
        .refreshable { await model.reload() }
    }
}
