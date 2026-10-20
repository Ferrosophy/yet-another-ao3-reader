import SwiftUI

/// 下載列表：顯示批次下載的進度，完成的檔案可分享或存到「檔案」。
struct DownloadsView: View {
    @Environment(AppState.self) private var app
    @State private var shared: DownloadedFile?

    var body: some View {
        let manager = app.downloads
        List {
            if manager.tasks.isEmpty {
                ContentUnavailableView("沒有下載項目", systemImage: "arrow.down.circle",
                                       description: Text("在「批次下載」中選擇作品後加入下載列表。下載的檔案也會出現在「檔案」App 的 YAAO3R 資料夾。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(manager.tasks) { task in
                Button {
                    if let file = task.file { shared = DownloadedFile(url: file) }
                    else if case .failed = task.state { manager.retry(task.id) }
                } label: {
                    HStack(spacing: 12) {
                        icon(task.state)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).foregroundStyle(.primary).lineLimit(2)
                            Text(detail(task)).appFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .disabled(task.state == .waiting || task.state == .downloading)
            }
            .onDelete { offsets in manager.remove(offsets.map { manager.tasks[$0].id }) }
        }
        .navigationTitle("下載列表")
        .toolbar {
            if manager.tasks.contains(where: { $0.state == .done }) {
                Button("清除已完成") { manager.clearFinished() }
            }
        }
        .sheet(item: $shared) { file in
            ActivityView(items: [file.url]).presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func icon(_ state: DownloadManager.State) -> some View {
        switch state {
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private func detail(_ task: DownloadManager.DownloadTask) -> String {
        switch task.state {
        case .waiting: String(localized: "等待中 · \(task.format.title)")
        case .downloading: String(localized: "下載中 · \(task.format.title)")
        case .done: String(localized: "已完成 · \(task.format.title) · 點擊分享")
        case .failed(let message): String(localized: "失敗：\(message)　點擊重試")
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

    private var limit: Int { DownloadManager.batchLimit }

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
                    LabeledContent("下載列表", value: app.downloads.activeCount > 0
                        ? String(localized: "\(app.downloads.activeCount) 項進行中") : "")
                }
            } footer: {
                Text("篩選條件與官網作品搜尋相同，可同時使用 Fandom、分級、標籤、字數、語言等多層條件。每次最多選取 \(limit) 部。")
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
                            selection = Array(works.prefix(count).map(\.id))
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
        .onAppear { if model == nil { showsFilters = true } }
    }

    private func row(_ work: WorkSummary) -> some View {
        let selected = selection.contains(work.id)
        return Button {
            if selected {
                selection.removeAll { $0 == work.id }
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
        let chosen = (model?.works ?? []).filter { selection.contains($0.id) }
        app.downloads.enqueue(chosen, format: format ?? defaultFormat, client: app.client)
        message = String(localized: "已加入下載列表：\(chosen.count) 部")
        selection = []
    }
}
