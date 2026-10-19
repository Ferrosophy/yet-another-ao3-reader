import Observation
import SwiftUI

/// 閱讀頁的帳號操作：書籤、稍後閱讀、訂閱作品 / 作者 / 系列。
/// 全部透過 AO3 官網表單提交，因此會直接同步到 AO3 帳號。
@MainActor
@Observable
final class WorkActionsModel {
    private(set) var actions: WorkActions?
    private(set) var authors: [SubscriptionTarget] = []
    private(set) var series: [SubscriptionTarget] = []
    private(set) var isBusy = false
    var message: String?

    private let workID: Int
    private let client: AO3Client

    init(workID: Int, client: AO3Client) {
        self.workID = workID
        self.client = client
    }

    /// 以作品頁解析出的狀態初始化，並在背景讀取作者與系列的訂閱狀態。
    func load(from detail: WorkDetail) async {
        actions = detail.actions
        guard actions != nil else { return }
        let client = client
        authors = detail.authorLinks.map { SubscriptionTarget(name: $0.name, path: Self.userPath($0.path)) }
        series = detail.series.map { SubscriptionTarget(name: $0.name, path: $0.path) }
        for (index, target) in authors.enumerated() {
            if let loaded = try? await client.subscriptionTarget(name: target.name, path: target.path) { authors[index] = loaded }
        }
        for (index, target) in series.enumerated() {
            if let loaded = try? await client.subscriptionTarget(name: target.name, path: target.path) { series[index] = loaded }
        }
    }

    /// 作者連結為 /users/<name>/pseuds/<pseud>，訂閱按鈕在 /users/<name>。
    private static func userPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "users" else { return path }
        return "/users/\(parts[1])"
    }

    func toggleMarkForLater() async {
        guard let form = actions?.mark else { return }
        let marked = actions?.isMarkedForLater ?? false
        await perform(marked ? "已標記為已讀" : "已加入稍後閱讀") { try await self.client.submit(form) }
    }

    func toggleWorkSubscription() async {
        guard let form = actions?.subscribe else { return }
        let subscribed = actions?.isSubscribed ?? false
        await perform(subscribed ? "已取消訂閱作品" : "已訂閱作品") { try await self.client.submit(form) }
    }

    func toggleSubscription(_ target: SubscriptionTarget) async {
        guard let form = target.form else { return }
        let subscribed = target.isSubscribed
        await perform(subscribed ? "已取消訂閱 \(target.name)" : "已訂閱 \(target.name)") {
            try await self.client.submit(form)
        }
        if let loaded = try? await client.subscriptionTarget(name: target.name, path: target.path) {
            if let index = authors.firstIndex(where: { $0.path == target.path }) { authors[index] = loaded }
            if let index = series.firstIndex(where: { $0.path == target.path }) { series[index] = loaded }
        }
    }

    func saveBookmark(notes: String, tags: String, isPrivate: Bool) async {
        guard let actions, let form = actions.bookmark else { return }
        let isUpdate = actions.isBookmarked
        await perform(isUpdate ? "書籤已更新" : "已加入書籤") {
            try await self.client.saveBookmark(form, notes: notes, tags: tags, isPrivate: isPrivate, isUpdate: isUpdate)
        }
    }

    func deleteBookmark() async {
        guard let actions, let form = actions.bookmark, actions.isBookmarked, let token = actions.authenticityToken else { return }
        await perform("已移除書籤") { try await self.client.deleteBookmark(form, token: token) }
    }

    private func perform(_ success: String, _ operation: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            actions = try await client.workActions(id: workID) ?? actions
            message = success
        } catch {
            message = "操作失敗：\(error.localizedDescription)"
        }
    }
}

/// 閱讀頁右上角的操作選單。
struct WorkActionsMenu: View {
    let model: WorkActionsModel
    @State private var showsBookmark = false

    var body: some View {
        Menu {
            if let actions = model.actions {
                Section("作品") {
                    Button(actions.isBookmarked ? "編輯書籤" : "加入書籤",
                           systemImage: actions.isBookmarked ? "bookmark.fill" : "bookmark") {
                        showsBookmark = true
                    }
                    .disabled(actions.bookmark == nil)
                    if actions.mark != nil {
                        Button(actions.isMarkedForLater ? "標記為已讀" : "稍後閱讀",
                               systemImage: actions.isMarkedForLater ? "checkmark.circle" : "clock.badge.plus") {
                            Task { await model.toggleMarkForLater() }
                        }
                    }
                    if actions.subscribe != nil {
                        Button(actions.isSubscribed ? "取消訂閱作品" : "訂閱作品",
                               systemImage: actions.isSubscribed ? "bell.slash" : "bell") {
                            Task { await model.toggleWorkSubscription() }
                        }
                    }
                }
                if !model.authors.isEmpty {
                    Section("作者") {
                        ForEach(model.authors) { target in subscriptionButton(target) }
                    }
                }
                if !model.series.isEmpty {
                    Section("系列") {
                        ForEach(model.series) { target in subscriptionButton(target) }
                    }
                }
            }
        } label: {
            if model.isBusy {
                ProgressView()
            } else {
                Label("帳號操作", systemImage: "ellipsis.circle")
            }
        }
        .disabled(model.actions == nil)
        .sheet(isPresented: $showsBookmark) {
            if let actions = model.actions {
                BookmarkSheet(model: model, actions: actions)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func subscriptionButton(_ target: SubscriptionTarget) -> some View {
        if target.form != nil {
            Button(target.isSubscribed ? "取消訂閱 \(target.name)" : "訂閱 \(target.name)",
                   systemImage: target.isSubscribed ? "bell.slash" : "bell") {
                Task { await model.toggleSubscription(target) }
            }
        } else {
            Text("\(target.name)（讀取中或無法訂閱）")
        }
    }
}

private struct BookmarkSheet: View {
    let model: WorkActionsModel
    let actions: WorkActions
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var tags = ""
    @State private var isPrivate = false

    var body: some View {
        NavigationStack {
            Form {
                Section("備註") {
                    TextEditor(text: $notes).frame(minHeight: 100)
                }
                Section {
                    TextField("你的標籤（以逗號分隔）", text: $tags)
                        .textInputAutocapitalization(.never)
                    Toggle("私人書籤", isOn: $isPrivate)
                }
                if actions.isBookmarked {
                    Section {
                        Button("移除書籤", role: .destructive) {
                            Task {
                                await model.deleteBookmark()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(actions.isBookmarked ? "編輯書籤" : "加入書籤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task {
                            await model.saveBookmark(notes: notes, tags: tags, isPrivate: isPrivate)
                            dismiss()
                        }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .onAppear {
                notes = actions.bookmarkNotes
                tags = actions.bookmarkTags
                isPrivate = actions.bookmarkPrivate
            }
        }
    }
}
