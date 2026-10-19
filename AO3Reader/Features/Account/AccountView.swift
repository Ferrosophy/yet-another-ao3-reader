import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var app

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
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text(username).font(.title3.bold())
                        Text(app.sources.selected.baseURL.host() ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("我的 AO3") {
                ForEach(UserListKind.allCases) { kind in
                    NavigationLink {
                        UserWorkListView(kind: kind, username: username)
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
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
    }
}

struct UserWorkListView: View {
    let kind: UserListKind
    let username: String
    @Environment(AppState.self) private var app
    @State private var model: PagedWorksModel?

    var body: some View {
        Group {
            if let model { WorkListView(model: model) } else { ProgressView() }
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
