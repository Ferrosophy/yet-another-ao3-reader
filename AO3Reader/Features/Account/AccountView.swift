import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var app
    @AppStorage("account.entryOrder") private var entryOrder = ""
    @AppStorage(DataSource.storageKey) private var dataSource: DataSource = .ao3
    @State private var editMode: EditMode = .inactive
    /// 切換器自己的選擇：先讓切換動畫跑完，再淡入另一邊的內容，避免整頁重建打斷動畫
    @State private var pickerSource: DataSource = DataSource.current

    var body: some View {
        Group {
            if dataSource == .local {
                LocalAccountView()
                    .transition(.opacity)
            } else if let username = app.auth.username {
                loggedIn(username)
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .navigationTitle("帳號")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 使用者資料只能二選一：AO3 帳號，或本機保存（可經 iCloud / WebDAV 同步）。
            // 放在導覽列中間，不另外疊一層背景（避免與大標題的模糊背景重疊）
            ToolbarItem(placement: .principal) {
                Picker("使用者資料", selection: $pickerSource) {
                    ForEach(DataSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .onChange(of: pickerSource) { _, source in
            guard source != dataSource else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeInOut(duration: 0.25)) { dataSource = source }
            }
        }
        .onChange(of: dataSource) { _, source in
            if pickerSource != source { pickerSource = source }
            if source == .local { Task { await app.librarySync.syncNow() } }
        }
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
        case .bookmarks: UserListKind.bookmarks.title
        case .markedForLater: UserListKind.markedForLater.title
        case .history: UserListKind.history.title
        case .subscriptions: String(localized: "訂閱")
        case .inbox: String(localized: "收件匣")
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
            let model = PagedWorksModel { page in
                var result = try await client.userList(kind, username: username, page: page)
                // 閱讀紀錄只顯示最近 100 部（AO3 每頁 20 部）
                if kind == .history, page * 20 >= LocalLibrary.historyLimit { result.hasNextPage = false }
                return result
            }
            self.model = model
            await model.reload()
        }
    }
}

/// 資料來源為「本機保存」時的帳號頁：本機的書籤、稍後閱讀、閱讀紀錄與訂閱（沒有收件匣）。
struct LocalAccountView: View {
    @Environment(AppState.self) private var app
    @AppStorage("account.entryOrder") private var entryOrder = ""
    @State private var editMode: EditMode = .inactive
    @State private var importStatus: String?
    @State private var isImporting = false

    private var entries: [AccountEntry] { AccountEntry.decode(entryOrder).filter { $0 != .inbox } }

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    NavigationLink {
                        entry.localDestination
                    } label: {
                        HStack {
                            Label(entry.title, systemImage: entry.systemImage)
                            Spacer()
                            Text(verbatim: "\(count(entry))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .onMove { source, destination in
                    // 收件匣在本機模式不顯示，保留它在完整順序中的位置
                    let inboxIndex = AccountEntry.decode(entryOrder).firstIndex(of: .inbox) ?? entries.count
                    var order = entries
                    order.move(fromOffsets: source, toOffset: destination)
                    order.insert(.inbox, at: min(inboxIndex, order.count))
                    entryOrder = AccountEntry.encode(order)
                }
            } header: {
                HStack {
                    Text("本機資料")
                    Spacer()
                    Button(editMode.isEditing ? "完成" : "排序") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .appFont(.footnote, weight: .medium)
                    .textCase(nil)
                }
            }

            Section {
                NavigationLink("資料同步") { SyncSettingsView() }
            } footer: {
                Text("本機資料只保存在這台裝置，可在「資料同步」選擇用 iCloud 或 WebDAV 同步到其他裝置。")
            }

            Section {
                Button {
                    runImport()
                } label: {
                    HStack {
                        Text("從 AO3 帳號匯入")
                        Spacer()
                        if isImporting { ProgressView() }
                    }
                }
                .disabled(isImporting || app.auth.username == nil)
                if let importStatus {
                    Text(importStatus).appFont(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text(app.auth.username == nil
                     ? String(localized: "需要先切換到「AO3 帳號」並登入，才能匯入。")
                     : String(localized: "把 AO3 帳號的書籤、稍後閱讀、閱讀紀錄與訂閱複製到本機，只新增本機沒有的項目，不會修改 AO3 帳號。"))
            }
        }
        .environment(\.editMode, $editMode)
    }

    private func count(_ entry: AccountEntry) -> Int {
        switch entry {
        case .bookmarks: app.library.library.bookmarks.count
        case .markedForLater: app.library.library.later.count
        case .history: app.library.library.history.count
        case .subscriptions: app.library.library.subscriptions.count
        case .inbox: 0
        }
    }

    private func runImport() {
        isImporting = true
        importStatus = nil
        Task {
            defer { isImporting = false }
            do {
                try await app.importFromAO3 { importStatus = $0 }
                importStatus = String(localized: "匯入完成")
            } catch {
                importStatus = String(localized: "匯入失敗：\(error.localizedDescription)")
            }
        }
    }
}

extension AccountEntry {
    /// 本機模式的目的頁
    @MainActor @ViewBuilder
    var localDestination: some View {
        switch self {
        case .bookmarks: LocalWorkListView(kind: .bookmarks)
        case .markedForLater: LocalWorkListView(kind: .markedForLater)
        case .history: LocalWorkListView(kind: .history)
        case .subscriptions, .inbox: LocalSubscriptionsView()
        }
    }
}

/// 本機的書籤 / 稍後閱讀 / 閱讀紀錄列表，向左滑可移除。
struct LocalWorkListView: View {
    let kind: UserListKind
    @Environment(AppState.self) private var app
    @State private var model: PagedWorksModel?

    var body: some View {
        Group {
            if let model {
                WorkListView(model: model) { work in remove(work) }
            } else {
                AO3LoadingView()
            }
        }
        .navigationTitle(kind.title)
        .task {
            guard model == nil else { return }
            let works = currentWorks()
            let model = PagedWorksModel { page in WorkPage(works: works, page: 1, hasNextPage: false) }
            self.model = model
            await model.reload()
        }
    }

    private func currentWorks() -> [WorkSummary] {
        switch kind {
        case .bookmarks: app.library.library.bookmarks.map(\.work)
        case .markedForLater: app.library.library.later.map(\.work)
        case .history:
            // 列表帶上本機的閱讀時間，供「依時間跳轉」使用
            app.library.library.history.prefix(LocalLibrary.historyLimit).map { entry in
                var work = entry.work
                work.visitedAt = entry.date
                return work
            }
        }
    }

    private func remove(_ work: WorkSummary) {
        switch kind {
        case .bookmarks: app.library.removeBookmark(work.id)
        case .markedForLater: app.library.toggleLater(work)
        case .history: app.library.removeHistory(work.id)
        }
        let works = currentWorks()
        model?.replaceLoader { _ in WorkPage(works: works, page: 1, hasNextPage: false) }
        Task { await model?.reload() }
    }
}

/// 本機訂閱：作品、系列、作者；有更新時標示「有更新」，點進去後清除。
struct LocalSubscriptionsView: View {
    @Environment(AppState.self) private var app
    @State private var isChecking = false

    private var subscriptions: [LocalSubscription] { app.library.library.subscriptions }

    var body: some View {
        List {
            if subscriptions.isEmpty {
                ContentUnavailableView("沒有訂閱", systemImage: "bell",
                                       description: Text("在閱讀頁右上角的選單中可訂閱作品、系列或作者。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(subscriptions) { item in
                link(item) {
                    HStack {
                        Label(item.name, systemImage: icon(item.kind))
                            .lineLimit(2)
                        Spacer()
                        if item.hasUpdate {
                            Text("有更新")
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.tint, in: .capsule)
                        }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { app.library.markSubscriptionSeen(item.path) })
                .swipeActions {
                    Button("取消訂閱", systemImage: "bell.slash", role: .destructive) {
                        app.library.toggleSubscription(kind: item.kind, path: item.path, name: item.name)
                    }
                }
            }
        }
        .navigationTitle("訂閱")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isChecking = true
                    Task {
                        await app.checkLocalSubscriptions(force: true)
                        isChecking = false
                    }
                } label: {
                    if isChecking { ProgressView() } else { Label("檢查更新", systemImage: "arrow.clockwise") }
                }
                .disabled(isChecking)
            }
        }
    }

    @ViewBuilder
    private func link<Content: View>(_ item: LocalSubscription, @ViewBuilder label: () -> Content) -> some View {
        switch item.kind {
        case .work:
            NavigationLink(value: WorkRoute(id: AO3Paths.workID(fromPath: item.path) ?? 0, title: item.name), label: label)
        case .series:
            NavigationLink(value: WorkListRoute.series(name: item.name, path: item.path), label: label)
        case .user:
            NavigationLink(value: WorkListRoute.person(name: item.name, path: item.path), label: label)
        }
    }

    private func icon(_ kind: LocalSubscription.Kind) -> String {
        switch kind {
        case .work: "doc.text"
        case .series: "books.vertical"
        case .user: "person"
        }
    }
}
