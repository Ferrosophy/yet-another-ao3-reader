import SwiftUI

/// 收件匣：收到的評論（/users/<name>/inbox）。點擊可開啟評論所在的作品。
struct InboxView: View {
    let username: String
    @Environment(AppState.self) private var app
    @State private var unreadOnly = false
    @State private var model: PagedListModel<InboxComment>?

    var body: some View {
        Group {
            if let model {
                PagedListView(model: model, emptyTitle: unreadOnly ? "沒有未讀評論" : "收件匣是空的") { comment in
                    if let workID = comment.workID {
                        NavigationLink(value: WorkRoute(id: workID, title: comment.targetTitle)) { InboxRow(comment: comment) }
                    } else {
                        InboxRow(comment: comment)
                    }
                }
            } else {
                AO3LoadingView()
            }
        }
        .navigationTitle("收件匣")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $unreadOnly) {
                    Label("僅未讀", systemImage: unreadOnly ? "envelope.badge.fill" : "envelope.badge")
                }
                .toggleStyle(.button)
            }
        }
        .task(id: unreadOnly) {
            let client = app.client
            let username = username, unreadOnly = unreadOnly
            let model = PagedListModel<InboxComment> { page in
                try await client.inbox(username: username, unreadOnly: unreadOnly, page: page)
            }
            self.model = model
            await model.reload()
        }
    }
}

private struct InboxRow: View {
    let comment: InboxComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if comment.isUnread {
                    Circle().fill(.tint).frame(width: 8, height: 8)
                        .accessibilityLabel("未讀")
                }
                Text(comment.commenter).font(.headline)
                Spacer()
                if let posted = comment.posted {
                    Text(posted).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !comment.targetTitle.isEmpty {
                Label(comment.targetTitle, systemImage: "book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(comment.body)
                .font(.callout)
                .lineLimit(6)
        }
        .padding(.vertical, 2)
    }
}
