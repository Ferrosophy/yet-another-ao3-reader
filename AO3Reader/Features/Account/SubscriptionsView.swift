// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 訂閱列表：作品、系列、用戶（/users/<name>/subscriptions?type=…）。
struct SubscriptionsView: View {
    let username: String
    @Environment(AppState.self) private var app
    @State private var kind: SubscriptionItem.Kind = .works
    /// 每種類型各自保留一個列表，切換時立即顯示已載入的內容
    @State private var models: [SubscriptionItem.Kind: PagedListModel<SubscriptionItem>] = [:]

    var body: some View {
        Group {
            if let model = models[kind] {
                PagedListView(model: model, emptyTitle: "沒有\(kind.title)訂閱") { item in
                    link(item)
                }
                .id(kind)
            } else {
                AO3LoadingView()
            }
        }
        .navigationTitle("訂閱")
        .navigationBarTitleDisplayMode(.inline)
        // 類型切換固定在頂部，不放進列表（列表重建時切換器也會被重建，點擊容易失效）
        .safeAreaBar(edge: .top) {
            Picker("類型", selection: $kind) {
                ForEach(SubscriptionItem.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .task(id: kind) {
            guard models[kind] == nil else { return }
            let client = app.client
            let username = username, kind = kind
            let model = PagedListModel<SubscriptionItem> { page in
                try await client.subscriptions(username: username, kind: kind, page: page)
            }
            models[kind] = model
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
            Text(item.title).appFont(.headline)
            if let byline = item.byline {
                Text(byline).appFont(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
