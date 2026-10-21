// SPDX-License-Identifier: GPL-3.0-or-later
import Observation
import SwiftUI

/// 作品評論列表（整部作品，分頁載入）
@MainActor
@Observable
final class CommentsModel {
    let workID: Int
    let client: AO3Client
    private(set) var comments: [WorkComment] = []
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var error: String?
    private var page = 0

    init(workID: Int, client: AO3Client) {
        self.workID = workID
        self.client = client
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await client.comments(workID: workID, page: page + 1)
            let known = Set(comments.map(\.id))
            comments += result.comments.filter { !known.contains($0.id) }
            page = result.page
            hasMore = result.hasNextPage
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 評論的沉浸式翻譯：評論出現時排入佇列，短暫防抖後合併成批次送出
@MainActor
@Observable
final class CommentTranslator {
    var isEnabled: Bool
    @ObservationIgnored private var slots: [String: TranslationSlot] = [:]
    @ObservationIgnored private var texts: [String: String] = [:]
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private let settings: TranslationSettings
    @ObservationIgnored private let translator: TranslationService

    init(isEnabled: Bool, settings: TranslationSettings, translator: TranslationService) {
        self.isEnabled = isEnabled
        self.settings = settings
        self.translator = translator
    }

    func slot(_ id: String) -> TranslationSlot {
        if let slot = slots[id] { return slot }
        let slot = TranslationSlot()
        slots[id] = slot
        return slot
    }

    func request(_ id: String, text: String) {
        guard isEnabled, slot(id).value == nil else { return }
        texts[id] = text
        slot(id).value = .loading
        queue.append(id)
        scheduleFlush()
    }

    func retry(_ id: String, text: String) {
        slot(id).value = nil
        request(id, text: text)
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.flush()
        }
    }

    private func flush() async {
        defer {
            flushTask = nil
            if !queue.isEmpty { scheduleFlush() }
        }
        let provider: any TranslationProvider
        do {
            provider = try settings.makeProvider()
        } catch {
            for id in queue { slot(id).value = .failed(error.localizedDescription) }
            queue.removeAll()
            return
        }
        var batch: [String] = []
        var characters = 0
        while let id = queue.first {
            let length = texts[id]?.count ?? 0
            if !batch.isEmpty, characters + length > provider.maxBatchCharacters { break }
            queue.removeFirst()
            batch.append(id)
            characters += length
        }
        guard !batch.isEmpty else { return }
        do {
            let translated = try await translator.translate(batch.map { texts[$0] ?? "" }, provider: provider,
                                                            source: settings.config.sourceLanguage,
                                                            target: settings.config.targetLanguage)
            for (id, text) in zip(batch, translated) { slot(id).value = .done(text) }
        } catch {
            for id in batch { slot(id).value = .failed(error.localizedDescription) }
        }
    }
}

/// 評論頁：可閱讀評論並以沉浸式翻譯顯示譯文；回覆以縮排與連線顯示所屬的討論串，作者本人的評論加上標記。
/// 要留言請到原網站
struct CommentsSheet: View {
    @State private var model: CommentsModel
    @State private var translator: CommentTranslator
    @State private var webTarget: WebTarget?
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// 作品作者的名稱（用來標示作者本人的回覆）
    private let creators: Set<String>

    init(workID: Int, client: AO3Client, app: AppState, translates: Bool, creators: [String] = []) {
        self.creators = Self.names(creators)
        _model = State(initialValue: CommentsModel(workID: workID, client: client))
        _translator = State(initialValue: CommentTranslator(isEnabled: translates, settings: app.translation,
                                                            translator: app.translator))
    }

    /// AO3 的作者名稱可能是「筆名 (帳號)」：兩者都拿來比對，不分大小寫
    private static func names(_ list: [String]) -> Set<String> {
        var result = Set<String>()
        for raw in list {
            let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { continue }
            result.insert(name)
            if let open = name.firstIndex(of: "("), name.hasSuffix(")") {
                result.insert(name[..<open].trimmingCharacters(in: .whitespaces))
                result.insert(String(name[name.index(after: open)..<name.index(before: name.endIndex)]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.comments) { comment in
                    CommentRow(comment: comment, translator: translator, accent: app.appearance.accentColor,
                               isCreator: !comment.isGuest && !Self.names([comment.author]).isDisjoint(with: creators))
                        // 同一串討論之間不加分隔線，只在頂層評論之前分隔
                        .listRowSeparator(comment.depth > 0 ? .hidden : .automatic, edges: .top)
                }
                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        Button("重試") { Task { await model.loadMore() } }
                    }
                } else if model.hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await model.loadMore() } }
                }
                Section {
                } footer: {
                    Text("要留言請點右上角，在原網站登入後留下評論。")
                }
            }
            .listStyle(.plain)
            .overlay {
                if model.comments.isEmpty, !model.hasMore, model.error == nil {
                    ContentUnavailableView("還沒有評論", systemImage: "text.bubble")
                }
            }
            .navigationTitle("評論")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        translator.isEnabled.toggle()
                    } label: {
                        Label("翻譯", systemImage: translator.isEnabled ? "character.bubble.fill" : "character.bubble")
                    }
                    Button("在網頁中打開", systemImage: "safari") {
                        webTarget = WebTarget(url: model.client.url("/works/\(model.workID)", query: [
                            URLQueryItem(name: "show_comments", value: "true"),
                            URLQueryItem(name: "view_full_work", value: "true"),
                        ]))
                    }
                }
            }
            .sheet(item: $webTarget) { WebPageSheet(url: $0.url) }
        }
    }
}

private struct CommentRow: View {
    let comment: WorkComment
    let translator: CommentTranslator
    let accent: Color
    /// 評論者是作品的作者
    let isCreator: Bool

    private static let indent: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: comment.author)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(isCreator ? AnyShapeStyle(accent) : AnyShapeStyle(.primary))
                if isCreator {
                    Text("作者")
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent, in: .capsule)
                }
                if comment.isGuest {
                    Text("訪客").appFont(.caption2).foregroundStyle(.secondary)
                }
            }
            if comment.depth > 0, let replyTo = comment.replyTo {
                Label("回覆 \(replyTo)", systemImage: "arrowshape.turn.up.left")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            if !comment.posted.isEmpty {
                Text(verbatim: comment.posted).appFont(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: comment.text).appFont(.body).textSelection(.enabled)
            if translator.isEnabled {
                CommentTranslationView(slot: translator.slot(comment.id), accent: accent) {
                    translator.retry(comment.id, text: comment.text)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(min(comment.depth, 4)) * Self.indent)
        // 每一層回覆畫一條線，連成同一串討論
        .overlay(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<min(comment.depth, 4), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .frame(width: Self.indent, alignment: .leading)
                }
            }
        }
        .task(id: translator.isEnabled) {
            if translator.isEnabled { translator.request(comment.id, text: comment.text) }
        }
    }
}

/// 只觀察單一評論的譯文
private struct CommentTranslationView: View {
    let slot: TranslationSlot
    let accent: Color
    var onRetry: () -> Void

    var body: some View {
        switch slot.value {
        case .loading:
            ProgressView().controlSize(.small)
        case .done(let text):
            Text(verbatim: text)
                .appFont(.body)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
                .textSelection(.enabled)
        case .failed(let message):
            Button {
                onRetry()
            } label: {
                Label("翻譯失敗：\(message)", systemImage: "arrow.clockwise").appFont(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }
}
