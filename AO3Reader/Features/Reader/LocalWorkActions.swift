// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 資料來源為「本機保存」時，閱讀頁右上角的操作選單：書籤、稍後閱讀、訂閱作品 / 作者 / 系列，
/// 全部寫入本機資料，不經 AO3 帳號。
struct LocalWorkActionsMenu: View {
    let detail: WorkDetail
    @Environment(AppState.self) private var app
    @State private var showsBookmark = false

    var body: some View {
        let library = app.library
        let work = detail.summaryInfo
        Menu {
            Section("作品") {
                Button(library.bookmark(detail.id) != nil ? "編輯書籤" : "加入書籤",
                       systemImage: library.bookmark(detail.id) != nil ? "bookmark.fill" : "bookmark") {
                    showsBookmark = true
                }
                Button(library.isMarkedForLater(detail.id) ? "標記為已讀" : "稍後閱讀",
                       systemImage: library.isMarkedForLater(detail.id) ? "checkmark.circle" : "clock") {
                    library.toggleLater(work)
                }
                subscriptionButton(kind: .work, path: "/works/\(detail.id)", name: detail.title,
                                   subscribe: String(localized: "訂閱作品"), unsubscribe: String(localized: "取消訂閱作品"))
            }
            if !detail.authorLinks.isEmpty {
                Section("作者") {
                    ForEach(detail.authorLinks, id: \.path) { author in
                        let path = Self.userPath(author.path)
                        subscriptionButton(kind: .user, path: path, name: author.name,
                                           subscribe: String(localized: "訂閱 \(author.name)"),
                                           unsubscribe: String(localized: "取消訂閱 \(author.name)"))
                    }
                }
            }
            if !detail.series.isEmpty {
                Section("系列") {
                    ForEach(detail.series, id: \.path) { series in
                        subscriptionButton(kind: .series, path: series.path, name: series.name,
                                           subscribe: String(localized: "訂閱 \(series.name)"),
                                           unsubscribe: String(localized: "取消訂閱 \(series.name)"))
                    }
                }
            }
        } label: {
            Label("本機操作", systemImage: "ellipsis.circle")
        }
        .sheet(isPresented: $showsBookmark) {
            LocalBookmarkSheet(work: work)
                .presentationDetents([.medium, .large])
        }
    }

    private func subscriptionButton(kind: LocalSubscription.Kind, path: String, name: String,
                                    subscribe: String, unsubscribe: String) -> some View {
        let subscribed = app.library.subscription(path) != nil
        return Button(subscribed ? unsubscribe : subscribe, systemImage: subscribed ? "bell.slash" : "bell") {
            app.library.toggleSubscription(kind: kind, path: path, name: name)
        }
    }

    /// 作者連結為 /users/<name>/pseuds/<pseud>，訂閱對象為 /users/<name>
    private static func userPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "users" else { return path }
        return "/users/\(parts[1])"
    }
}

/// 本機書籤的備註、自訂標籤與私人設定。
private struct LocalBookmarkSheet: View {
    let work: WorkSummary
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var tags = ""
    @State private var isPrivate = false

    var body: some View {
        let existing = app.library.bookmark(work.id)
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
                if existing != nil {
                    Section {
                        Button("移除書籤", role: .destructive) {
                            app.library.removeBookmark(work.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing != nil ? "編輯書籤" : "加入書籤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        app.library.saveBookmark(work, notes: notes, tags: tags, isPrivate: isPrivate)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .onAppear {
                notes = existing?.notes ?? ""
                tags = existing?.tags ?? ""
                isPrivate = existing?.isPrivate ?? false
            }
        }
    }
}
