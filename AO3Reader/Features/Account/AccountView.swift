import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var app
    @AppStorage("account.entryOrder") private var entryOrder = ""
    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            if let username = app.auth.username {
                loggedIn(username)
            } else {
                LoginView()
            }
        }
        .navigationTitle("帳號")
    }

    private func loggedIn(_ username: String) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AvatarView(url: app.auth.avatarURL)
                    VStack(alignment: .leading) {
                        Text(username).appFont(.title3, weight: .bold)
                        Text(app.sources.selected.baseURL.host() ?? "")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(entries) { entry in
                    NavigationLink {
                        entry.destination(username: username)
                    } label: {
                        Label(entry.title, systemImage: entry.systemImage)
                    }
                }
                .onMove { source, destination in
                    var order = entries
                    order.move(fromOffsets: source, toOffset: destination)
                    entryOrder = AccountEntry.encode(order)
                }
            } header: {
                HStack {
                    Text("我的 AO3")
                    Spacer()
                    Button(editMode.isEditing ? "完成" : "排序") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .appFont(.footnote, weight: .medium)
                    .textCase(nil)
                }
            }

            Section {
                Button("登出", role: .destructive) {
                    Task { await app.auth.logout(client: app.client) }
                }
            } footer: {
                Text("登入狀態以 AO3 的 Cookie 保存在本機，依來源網域分開。本應用沒有自己的帳號系統，也不保存你的密碼。")
            }
        }
        .environment(\.editMode, $editMode)
        .task(id: username) {
            if app.auth.avatarURL == nil { await app.auth.loadAvatar(client: app.client) }
        }
    }

    private var entries: [AccountEntry] { AccountEntry.decode(entryOrder) }
}

/// 「我的 AO3」的項目，順序可由使用者自訂。
enum AccountEntry: String, CaseIterable, Identifiable {
    case bookmarks, markedForLater, history, subscriptions, inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bookmarks: AO3Term.label(UserListKind.bookmarks.title, "Bookmarks")
        case .markedForLater: AO3Term.label(UserListKind.markedForLater.title, "Marked for Later")
        case .history: AO3Term.label(UserListKind.history.title, "History")
        case .subscriptions: AO3Term.label(String(localized: "訂閱"), "Subscriptions")
        case .inbox: AO3Term.label(String(localized: "收件匣"), "Inbox")
        }
    }

    var systemImage: String {
        switch self {
        case .bookmarks: UserListKind.bookmarks.systemImage
        case .markedForLater: UserListKind.markedForLater.systemImage
        case .history: UserListKind.history.systemImage
        case .subscriptions: "bell"
        case .inbox: "tray"
        }
    }

    @MainActor @ViewBuilder
    func destination(username: String) -> some View {
        switch self {
        case .bookmarks: UserWorkListView(kind: .bookmarks, username: username)
        case .markedForLater: UserWorkListView(kind: .markedForLater, username: username)
        case .history: UserWorkListView(kind: .history, username: username)
        case .subscriptions: SubscriptionsView(username: username)
        case .inbox: InboxView(username: username)
        }
    }

    /// 解析保存的順序；缺少的項目（例如日後新增）補在最後
    static func decode(_ stored: String) -> [AccountEntry] {
        var order = stored.split(separator: ",").compactMap { AccountEntry(rawValue: String($0)) }
        order = order.enumerated().filter { order.firstIndex(of: $0.element) == $0.offset }.map(\.element)
        return order + allCases.filter { !order.contains($0) }
    }

    static func encode(_ order: [AccountEntry]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }
}

/// 帳號頭像：有 AO3 頭像時載入，否則顯示預設圖示。
struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.tint)
    }
}

struct UserWorkListView: View {
    let kind: UserListKind
    let username: String
    @Environment(AppState.self) private var app
    @State private var model: PagedWorksModel?

    var body: some View {
        Group {
            if let model { WorkListView(model: model) } else { AO3LoadingView() }
        }
        .navigationTitle(kind.title)
        .task {
            guard model == nil else { return }
            let client = app.client
            let kind = kind, username = username
            let model = PagedWorksModel { page in try await client.userList(kind, username: username, page: page) }
            self.model = model
            await model.reload()
        }
    }
}
