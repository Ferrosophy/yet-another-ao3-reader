import SwiftUI

/// 訂閱列表：作品、系列、用戶（/users/<name>/subscriptions?type=…）。
struct SubscriptionsView: View {
    let username: String
    @Environment(AppState.self) private var app
    @State private var kind: SubscriptionItem.Kind = .works
    @State private var model: PagedListModel<SubscriptionItem>?

    var body: some View {
        Group {
            if let model {
                PagedListView(model: model, emptyTitle: "沒有\(kind.title)訂閱") { item in
                    link(item)
                }
            } else {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("類型", selection: $kind) {
                ForEach(SubscriptionItem.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("訂閱")
        .task(id: kind) {
            let client = app.client
            let username = username, kind = kind
            let model = PagedListModel<SubscriptionItem> { page in
                try await client.subscriptions(username: username, kind: kind, page: page)
            }
            self.model = model
            await model.reload()
        }
    }

    /// 不同類型導向不同的 route 型別，NavigationLink 需各自宣告才能對應 navigationDestination。
    @ViewBuilder
    private func link(_ item: SubscriptionItem) -> some View {
        switch item.kind {
        case .works:
            if let id = item.workID {
                NavigationLink(value: WorkRoute(id: id, title: item.title)) { row(item) }
            } else {
                row(item)
            }
        case .series:
            NavigationLink(value: WorkListRoute.series(name: item.title, path: item.path)) { row(item) }
        case .users:
            NavigationLink(value: WorkListRoute.person(name: item.title, path: item.path)) { row(item) }
        }
    }

    private func row(_ item: SubscriptionItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline)
            if let byline = item.byline {
                Text(byline).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
