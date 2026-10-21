// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 下載列表：書架作品的離線進度（下載原文、翻譯、匯出），可暫停、繼續與重試。
/// 匯出檔也會出現在「檔案」App 的 YAAO3R › Bookshelf 資料夾。
struct DownloadsView: View {
    @Environment(AppState.self) private var app
    @State private var shared: DownloadedFile?

    var body: some View {
        let offline = app.offline
        let items = app.bookshelf.sorted(by: .added, ascending: false)
        let active = items.filter { offline.activity[$0.id] != nil }
        let done = items.filter { offline.activity[$0.id] == nil && offline.hasOfflineCopy($0.id) }
        List {
            if active.isEmpty && done.isEmpty {
                ContentUnavailableView("沒有下載項目", systemImage: "arrow.down.circle",
                                       description: Text("離線保存的作品會先下載原文，再自動翻譯，並以選擇的格式保存。"))
                    .listRowBackground(Color.clear)
            }
            if !active.isEmpty {
                Section("進行中") {
                    ForEach(active) { item in row(item) }
                }
            }
            if !done.isEmpty {
                Section {
                    ForEach(done) { item in row(item) }
                } header: {
                    Text("已離線")
                } footer: {
                    Text("共 \(ByteCountFormatter.string(fromByteCount: offline.totalSize, countStyle: .file))")
                }
            }
        }
        .navigationTitle("下載列表")
        .sheet(item: $shared) { file in
            ActivityView(items: [file.url]).presentationDetents([.medium, .large])
        }
    }

    private func row(_ item: BookshelfItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.work.title).lineLimit(2)
            OfflineStatusView(id: item.id)
        }
        .contextMenu { OfflineMenu(id: item.id, shared: $shared) }
        .swipeActions {
            if let url = app.offline.exportURL(item.id) {
                Button("分享", systemImage: "square.and.arrow.up") { shared = DownloadedFile(url: url) }
            }
        }
    }
}

/// 一部作品的離線狀態：進度、格式、大小與譯文語言。
struct OfflineStatusView: View {
    let id: Int
    @Environment(AppState.self) private var app

    var body: some View {
        let offline = app.offline
        VStack(alignment: .leading, spacing: 4) {
            if case .translating(let done, let total) = offline.activity[id], total > 0 {
                ProgressView(value: Double(done), total: Double(total))
            } else if case .downloadingChapters(let done, let total) = offline.activity[id], total > 0 {
                ProgressView(value: Double(done), total: Double(total))
            }
            HStack(spacing: 6) {
                if offline.activity[id]?.isActive == true {
                    ProgressView().controlSize(.mini)
                } else if let icon {
                    Image(systemName: icon.0).foregroundStyle(icon.1)
                }
                Text(text)
                    .lineLimit(2)
            }
            .appFont(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var icon: (String, Color)? {
        switch app.offline.activity[id] {
        case .paused: return ("pause.circle.fill", Color.secondary)
        case .waitingForWiFi: return ("wifi", Color.secondary)
        case .awaitingConsent: return ("exclamationmark.circle.fill", Color.orange)
        case .failed: return ("exclamationmark.triangle.fill", Color.red)
        default: return app.offline.hasOfflineCopy(id) ? ("checkmark.circle.fill", Color.green) : nil
        }
    }

    private var text: String { Self.describe(id: id, offline: app.offline, targetLanguageCode: app.translation.config.targetLanguageCode) }

    /// 離線狀態的文字說明（列表、卡片與長按選單共用）
    static func describe(id: Int, offline: OfflineManager, targetLanguageCode: String) -> String {
        switch offline.activity[id] {
        case .queued: return String(localized: "等待中")
        case .downloading: return String(localized: "正在下載原文")
        case .downloadingChapters(let done, let total): return String(localized: "正在逐章下載原文 \(done)/\(total)")
        case .translating(let done, let total): return String(localized: "正在翻譯 \(done)/\(total)")
        case .exporting: return String(localized: "正在匯出")
        case .paused: return String(localized: "已暫停")
        case .waitingForWiFi: return String(localized: "等待 Wi-Fi 連線")
        case .awaitingConsent: return String(localized: "翻譯會使用付費 API，長按確認後開始")
        case .failed(let message): return message
        case nil: break
        }
        guard let record = offline.records[id], record.downloadedAt != nil else { return String(localized: "未離線") }
        var parts = [String(localized: "已離線")]
        if let format = record.format { parts.append(format.title) }
        if let size = offline.sizes[id] { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if offline.isSameLanguage(record.originalLanguage) {
            parts.append(String(localized: "原文即目標語言"))
        } else if let language = record.translatedLanguage {
            if language != targetLanguageCode {
                parts.append(String(localized: "譯文為\(TranslationLanguage.named(language).displayName)"))
            } else if !record.isTranslationComplete {
                parts.append(String(localized: "已翻譯 \(record.translatedCount)/\(record.translatableCount)"))
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// 離線內容的操作：暫停 / 繼續 / 重試、檢查新章節、重新翻譯、更換格式、分享與刪除。
struct OfflineMenu: View {
    let id: Int
    @Binding var shared: DownloadedFile?
    @Environment(AppState.self) private var app

    private func share(bilingual: Bool) {
        if let url = app.offline.shareFile(id, bilingual: bilingual) { shared = DownloadedFile(url: url) }
    }

    var body: some View {
        let offline = app.offline
        let record = offline.records[id]
        switch offline.activity[id] {
        case .queued, .downloading, .downloadingChapters, .translating, .exporting:
            Button("暫停", systemImage: "pause") { offline.pause(id) }
        case .paused, .waitingForWiFi:
            Button("繼續", systemImage: "play") { offline.resume(id) }
        case .failed:
            Button("重試", systemImage: "arrow.clockwise") { offline.resume(id) }
        case .awaitingConsent:
            Button("使用付費 API 翻譯", systemImage: "checkmark.circle") { offline.consent(id) }
        case nil:
            if record?.downloadedAt == nil {
                Button("重新下載", systemImage: "arrow.down.circle") { offline.update(id) }
            }
        }
        if offline.hasOfflineCopy(id) {
            Menu("分享", systemImage: "square.and.arrow.up") {
                Button("原文") { share(bilingual: false) }
                Button("原文與譯文") { share(bilingual: true) }
            }
            Button("檢查新章節", systemImage: "arrow.triangle.2.circlepath") { offline.update(id) }
            Button("重新翻譯", systemImage: "translate") { offline.retranslate(id) }
            Menu("匯出格式", systemImage: "doc") {
                ForEach(DownloadFormat.allCases) { format in
                    Button {
                        offline.setFormat(format, for: id)
                    } label: {
                        if format == record?.format {
                            Label(format.title, systemImage: "checkmark")
                        } else {
                            Text(verbatim: format.title)
                        }
                    }
                }
            }
        }
    }
}

/// 批次下載：以官網搜尋條件多層篩選，列出符合的作品，手動或依順序選取（每次最多 25 部）後加入下載列表。
struct BatchDownloadView: View {
    enum ListOrder: String, CaseIterable, Identifiable {
        case ao3, kudos, hits, words
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ao3: String(localized: "依搜尋排序")
            case .kudos: "Kudos"
            case .hits: AO3Term.label(String(localized: "點擊"), "Hits")
            case .words: String(localized: "字數")
            }
        }
    }

    @Environment(AppState.self) private var app
    @AppStorage(DownloadFormat.storageKey) private var defaultFormat: DownloadFormat = .epub
    @State private var query = WorkSearchQuery()
    @State private var showsFilters = false
    @State private var model: PagedWorksModel?
    @State private var selection: [Int] = []
    @State private var order: ListOrder = .ao3
    @State private var format: DownloadFormat?
    @State private var message: String?

    private var limit: Int { OfflineManager.batchLimit }
    /// 每 3 天的批次下載額度剩餘數（選取上限取兩者較小值）
    @State private var remaining = BatchDownloadQuota.remaining()
    private var selectionLimit: Int { min(limit, remaining) }

    private var quotaMessage: String {
        if let date = BatchDownloadQuota.nextAvailable() {
            return String(localized: "3 天內最多批次下載 \(BatchDownloadQuota.limit) 部，額度將於 \(date.formatted(date: .abbreviated, time: .shortened)) 恢復")
        }
        return String(localized: "3 天內最多批次下載 \(BatchDownloadQuota.limit) 部，目前剩餘 \(remaining) 部")
    }

    private var works: [WorkSummary] {
        let works = model?.works ?? []
        func number(_ text: String?) -> Int { Int((text ?? "").filter(\.isNumber)) ?? 0 }
        switch order {
        case .ao3: return works
        case .kudos: return works.sorted { number($0.kudos) > number($1.kudos) }
        case .hits: return works.sorted { number($0.hits) > number($1.hits) }
        case .words: return works.sorted { number($0.words) > number($1.words) }
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showsFilters = true
                } label: {
                    Label(model == nil ? LocalizedStringKey("設定篩選條件") : "修改篩選條件", systemImage: "line.3.horizontal.decrease.circle")
                }
                Picker("下載格式", selection: Binding(get: { format ?? defaultFormat }, set: { format = $0 })) {
                    ForEach(DownloadFormat.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                NavigationLink {
                    DownloadsView()
                } label: {
                    let activeCount = app.offline.activity.values.filter(\.isActive).count
                    LabeledContent("下載列表", value: activeCount > 0 ? String(localized: "\(activeCount) 項進行中") : "")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("選取的作品會離線保存：先下載原文，再自動翻譯，並以選擇的格式保存。篩選條件與官網作品搜尋相同，可同時使用 Fandom、分級、標籤、字數、語言等多層條件。每次最多選取 \(limit) 部。")
                    Text(quotaMessage)
                }
            }

            if let model {
                Section {
                    Picker("列表排序", selection: $order) {
                        ForEach(ListOrder.allCases) { Text($0.title).tag($0) }
                    }
                    ForEach(works) { work in
                        row(work)
                            .task { await model.loadMoreIfNeeded(current: work) }
                    }
                    if model.isLoading { AO3LoadingView(compact: true) }
                    if let error = model.error, model.works.isEmpty {
                        Text(error).foregroundStyle(.red)
                    } else if model.hasLoaded, !model.isLoading, model.works.isEmpty {
                        Text("沒有符合條件的作品").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("搜尋結果")
                }
            }
        }
        .navigationTitle("批次下載")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach([5, 10, limit], id: \.self) { count in
                        Button(String(localized: "依目前順序選取前 \(count) 部")) {
                            selection = Array(works.prefix(min(count, selectionLimit)).map(\.id))
                            if count > selectionLimit { message = quotaMessage }
                        }
                    }
                    Button("取消全部選取", role: .destructive) { selection = [] }
                } label: {
                    Label("批量選取", systemImage: "checklist")
                }
                .disabled(model == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty {
                Button {
                    download()
                } label: {
                    Text("下載 \(selection.count) 部作品").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding()
            }
        }
        .overlay(alignment: .top) {
            if let message {
                Text(message)
                    .appFont(.subheadline, weight: .medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(query: $query, mode: .search) {
                showsFilters = false
                search()
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            remaining = BatchDownloadQuota.remaining()
            if model == nil { showsFilters = true }
        }
    }

    private func row(_ work: WorkSummary) -> some View {
        let selected = selection.contains(work.id)
        return Button {
            if selected {
                selection.removeAll { $0 == work.id }
            } else if selection.count >= remaining {
                message = quotaMessage
            } else if selection.count >= limit {
                message = String(localized: "每次最多選取 \(limit) 部")
            } else {
                selection.append(work.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title).foregroundStyle(.primary).lineLimit(2)
                    Text([work.authors.first, work.words.map { String(localized: "\($0) 字") }, work.kudos.map { "♥ \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func search() {
        selection = []
        let client = app.client
        let query = query
        let model = PagedWorksModel { page in try await client.searchWorks(query, page: page) }
        self.model = model
        Task { await model.reload() }
    }

    private func download() {
        let available = BatchDownloadQuota.remaining()
        let chosen = Array((model?.works ?? []).filter { selection.contains($0.id) }.prefix(available))
        guard !chosen.isEmpty else {
            remaining = available
            message = quotaMessage
            return
        }
        for work in chosen { app.offline.add(work, format: format ?? defaultFormat) }
        BatchDownloadQuota.record(chosen.count)
        remaining = BatchDownloadQuota.remaining()
        message = String(localized: "已離線保存：\(chosen.count) 部")
        selection = []
    }
}

/// 網格封面右上角的離線狀態標記：已離線為綠色勾，處理中為進度圈，暫停或等待為灰色，失敗為紅色驚嘆號。
/// 詳細資訊在長按選單中顯示。
struct OfflineBadge: View {
    let id: Int
    @Environment(AppState.self) private var app

    var body: some View {
        let offline = app.offline
        Group {
            switch offline.activity[id] {
            case .some(let activity) where activity.isActive:
                ProgressView().controlSize(.mini).tint(.white)
                    .frame(width: 20, height: 20)
                    .background(.black.opacity(0.45), in: .circle)
            case .failed:
                symbol("exclamationmark.circle.fill", .red)
            case .paused, .waitingForWiFi, .awaitingConsent:
                symbol("pause.circle.fill", .gray)
            default:
                if offline.hasOfflineCopy(id) { symbol("checkmark.circle.fill", .green) }
            }
        }
        .padding(6)
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
