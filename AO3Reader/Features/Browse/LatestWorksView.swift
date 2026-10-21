// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 首頁：最新作品，以及依 Kudos / 評論 / 點擊排序的排行榜（可選時間範圍）。
/// 全部以官網 Work Search 參數向 AO3 查詢；語言清單從官網搜尋表單讀取。
struct LatestWorksView: View {
    enum Board: String, CaseIterable, Identifiable {
        case latest, kudos, comments, hits
        var id: String { rawValue }
        var title: String {
            switch self {
            case .latest: String(localized: "最新")
            case .kudos: "Kudos"
            case .comments: String(localized: "評論")
            case .hits: String(localized: "點擊")
            }
        }
        var sort: WorkSearchQuery.SortColumn {
            switch self {
            case .latest: .dateUpdated
            case .kudos: .kudos
            case .comments: .comments
            case .hits: .hits
            }
        }
    }

    enum Period: String, CaseIterable, Identifiable {
        case day, week, month, year, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: String(localized: "24 小時")
            case .week: String(localized: "本週")
            case .month: String(localized: "本月")
            case .year: String(localized: "今年")
            case .all: String(localized: "全部")
            }
        }
        /// AO3 的相對日期語法（作用於最後更新時間）
        var revisedAt: String {
            switch self {
            case .day: "< 1 day"
            case .week: "< 1 week"
            case .month: "< 1 month"
            case .year: "< 1 year"
            case .all: ""
            }
        }
    }

    @Environment(AppState.self) private var app
    @AppStorage("latest.languageID") private var languageID = ""
    @AppStorage("latest.board") private var board: Board = .latest
    @AppStorage("latest.period") private var period: Period = .week
    /// 0 為全部分級
    @AppStorage("latest.rating") private var ratingID = 0
    @State private var model: PagedWorksModel?
    @State private var languages = LatestWorksView.cachedLanguages()
    @State private var showsLanguages = false
    @State private var showsGuide = false
    /// 目前顯示的卡片
    @State private var currentIndex = 0
    /// 上次載入的篩選條件；從作品頁返回時條件沒變就不重新載入，保留目前的卡片位置
    @State private var loadedKey: LoadKey?

    /// 特殊語言值：所有中文分支（普通話、粵語、吳語、閩南語、客家話、文言…）
    static let chineseAll = "@zh-all"

    private struct LoadKey: Equatable {
        var language: String
        var languageCount: Int
        var board: Board
        var period: Period
        var rating: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            // 固定在頂部的榜單與篩選，不隨卡片捲動
            filterBar
            cards
        }
        .navigationTitle(board == .latest ? "最新作品" : "\(board.title) 排行")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // 以目前的榜單與篩選重新載入，回到第一張卡片
                Button("重新整理", systemImage: "arrow.clockwise") {
                    currentIndex = 0
                    Task { await model?.reload(clear: true) }
                }
                .disabled(model?.isLoading ?? true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("AO3 說明", systemImage: "info.circle") { showsGuide = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                SummaryTranslationToggle()
            }
        }
        .sheet(isPresented: $showsGuide) {
            AO3GuideView()
        }
        .sheet(isPresented: $showsLanguages) {
            BrowseFilterSheet(languages: languages, selection: $languageID, rating: $ratingID, chineseAll: Self.chineseAll,
                              showsRating: false)
                .presentationDetents([.medium, .large])
        }
        .task {
            // 從官網讀取完整語言清單並快取
            if let loaded = try? await app.client.languages(), !loaded.isEmpty {
                languages = loaded
                UserDefaults.standard.set(try? JSONEncoder().encode(loaded), forKey: Self.languagesKey)
            }
        }
        .task(id: LoadKey(language: languageID, languageCount: languages.count, board: board, period: period, rating: ratingID)) {
            let key = LoadKey(language: languageID, languageCount: languages.count, board: board, period: period, rating: ratingID)
            guard key != loadedKey || model == nil || model?.needsReload == true else { return }
            loadedKey = key
            let client = app.client
            var query = WorkSearchQuery()
            query.sortColumn = board.sort
            query.sortDirection = .desc
            if languageID == Self.chineseAll {
                // AO3 的語言篩選只接受單一語言；關鍵字欄位支援 Elasticsearch 欄位查詢，以 OR 合併所有中文分支
                query.query = "language_id:(" + chineseCodes.joined(separator: " OR ") + ")"
            } else {
                query.languageID = languageID
            }
            if board != .latest { query.revisedAt = period.revisedAt }
            query.rating = WorkSearchQuery.Rating(rawValue: ratingID)
            let snapshot = query
            let loader: PagedWorksModel.Loader = { page in try await client.searchWorks(snapshot, page: page) }
            if let model {
                model.replaceLoader(loader)
            } else {
                model = PagedWorksModel(loader: loader)
            }
            currentIndex = 0
            // 篩選改變後立即清空舊卡片並重新載入
            await model?.reload(clear: true)
        }
    }

    /// 從 AO3 語言清單找出所有以「中文」開頭的語言；清單尚未載入時使用常見代碼
    private var chineseCodes: [String] {
        let codes = languages.filter { $0.name.hasPrefix("中文") }.map(\.code)
        return codes.count > 1 ? codes : ["zh", "yue", "wuu", "nan", "hak", "lzh"]
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            Picker("榜單", selection: $board) {
                ForEach(Board.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Menu {
                    Picker("分級", selection: $ratingID) {
                        Text("全部分級").tag(0)
                        ForEach(WorkSearchQuery.Rating.allCases) { rating in
                            Text(app.tags.translation(for: rating.title) ?? rating.title).tag(rating.rawValue)
                        }
                    }
                } label: {
                    chip(ratingName, systemImage: "shield.lefthalf.filled")
                }
                Button {
                    showsLanguages = true
                } label: {
                    chip(languageName, systemImage: "globe")
                }
                if board != .latest {
                    Menu {
                        Picker("時間範圍", selection: $period) {
                            ForEach(Period.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        chip(period.title, systemImage: "calendar")
                    }
                }
            }
            // 篩選按鈕平分整列寬度，與上方榜單左右對齊
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func chip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .appFont(.subheadline)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    /// 左右滑動的作品卡片；只有目前顯示的卡片會翻譯
    @ViewBuilder
    private var cards: some View {
        if let model {
            if let error = model.error, model.works.isEmpty {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重試") { Task { await model.reload() } }
                        .buttonStyle(.glassProminent)
                }
                .frame(maxHeight: .infinity)
            } else if model.works.isEmpty {
                if model.isLoading || !model.hasLoaded {
                    AO3LoadingView()
                } else {
                    ContentUnavailableView("沒有作品", systemImage: "books.vertical")
                        .frame(maxHeight: .infinity)
                }
            } else {
                WorkCardPager(works: model.works, currentIndex: $currentIndex, hasMore: model.hasNextPage,
                              loadUntil: { await model.loadUntil(count: $0) }) { last in
                    await model.loadMoreIfNeeded(current: last)
                }
            }
        } else {
            AO3LoadingView()
        }
    }

    private var ratingName: String {
        guard let rating = WorkSearchQuery.Rating(rawValue: ratingID) else { return String(localized: "全部分級") }
        return app.tags.translation(for: rating.title) ?? rating.title
    }

    private var languageName: String {
        if languageID == Self.chineseAll { return String(localized: "中文") }
        return languageID.isEmpty ? String(localized: "全部語言") : (languages.first { $0.code == languageID }?.name ?? languageID)
    }

    static let languagesKey = "ao3.languages"

    static func cachedLanguages() -> [AO3Language] {
        UserDefaults.standard.data(forKey: languagesKey)
            .flatMap { try? JSONDecoder().decode([AO3Language].self, from: $0) }
            .map(AO3Language.bySpeakers) ?? AO3Language.bySpeakers(AO3Language.fallback)
    }
}

/// 瀏覽頁的篩選：分級與作品語言放在同一個頁面（語言可搜尋，選項與 AO3 搜尋表單相同）。
struct BrowseFilterSheet: View {
    let languages: [AO3Language]
    @Binding var selection: String
    /// 0 為全部分級，其餘為 AO3 的分級 ID
    @Binding var rating: Int
    var chineseAll: String?
    /// 瀏覽頁的分級已有獨立選單，只顯示語言
    var showsRating = true
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [AO3Language] {
        guard !search.isEmpty else { return languages }
        return languages.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty, showsRating {
                    Section("分級") {
                        ratingRow(0, title: String(localized: "全部分級"), english: nil)
                        ForEach(WorkSearchQuery.Rating.allCases) { item in
                            ratingRow(item.rawValue, title: app.tags.translation(for: item.title) ?? item.title,
                                      english: app.tags.translation(for: item.title) == nil ? nil : item.title)
                        }
                    }
                }
                Section("作品語言") {
                    if search.isEmpty {
                        languageRow(code: "", name: "全部語言")
                        if let chineseAll {
                            languageRow(code: chineseAll, name: "中文")
                        }
                    }
                    ForEach(filtered) { language in
                        languageRow(code: language.code, name: LocalizedStringKey(language.name))
                    }
                }
            }
            .searchable(text: $search, prompt: "搜尋語言")
            .navigationTitle(showsRating ? "篩選" : "作品語言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func ratingRow(_ id: Int, title: String, english: String?) -> some View {
        Button {
            rating = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let english {
                        Text(verbatim: english).appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if rating == id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private func languageRow(code: String, name: LocalizedStringKey) -> some View {
        Button {
            selection = code
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selection == code { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}

/// 瀏覽頁的一張作品卡片：顯示完整簡介，內容過長時可在卡片內上下捲動；點擊進入作品。
struct BrowseCard: View {
    let work: WorkSummary
    let isCurrent: Bool
    var onDelete: ((WorkSummary) -> Void)?

    var body: some View {
        NavigationLink(value: WorkRoute(id: work.id, title: work.title)) {
            ScrollView {
                WorkRow(work: work, translationActive: isCurrent, compact: false)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            // 液態玻璃卡片：透明、不加底色
            .glassEffect(.clear, in: .rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookshelfMenuButton(work: work)
            if let onDelete {
                Button("移除", systemImage: "trash", role: .destructive) { onDelete(work) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
