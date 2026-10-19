import SwiftUI

/// 首頁：最新作品，以及依 Kudos / 評論 / 點擊排序的排行榜（可選時間範圍）。
/// 全部以官網 Work Search 參數向 AO3 查詢；語言清單從官網搜尋表單讀取。
struct LatestWorksView: View {
    enum Board: String, CaseIterable, Identifiable {
        case latest, kudos, comments, hits
        var id: String { rawValue }
        var title: String {
            switch self {
            case .latest: "最新"
            case .kudos: "Kudos"
            case .comments: "評論"
            case .hits: "點擊"
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
            case .day: "24 小時"
            case .week: "本週"
            case .month: "本月"
            case .year: "今年"
            case .all: "全部"
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
    @State private var model: PagedWorksModel?
    @State private var languages = LatestWorksView.cachedLanguages()
    @State private var showsLanguages = false

    private struct LoadKey: Equatable {
        var language: String
        var board: Board
        var period: Period
    }

    var body: some View {
        Group {
            if let model { WorkListView(model: model, showsHeading: false) } else { AO3LoadingView() }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                Picker("榜單", selection: $board) {
                    ForEach(Board.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if board != .latest {
                    Picker("時間範圍", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(board == .latest ? "最新作品" : "\(board.title) 排行")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsLanguages = true
                } label: {
                    Label(languageName, systemImage: "globe")
                }
            }
        }
        .sheet(isPresented: $showsLanguages) {
            LanguagePickerSheet(languages: languages, selection: $languageID)
                .presentationDetents([.medium, .large])
        }
        .task {
            // 從官網讀取完整語言清單並快取
            if let loaded = try? await app.client.languages(), !loaded.isEmpty {
                languages = loaded
                UserDefaults.standard.set(try? JSONEncoder().encode(loaded), forKey: Self.languagesKey)
            }
        }
        .task(id: LoadKey(language: languageID, board: board, period: period)) {
            let client = app.client
            var query = WorkSearchQuery()
            query.sortColumn = board.sort
            query.sortDirection = .desc
            query.languageID = languageID
            if board != .latest { query.revisedAt = period.revisedAt }
            let snapshot = query
            let loader: PagedWorksModel.Loader = { page in try await client.searchWorks(snapshot, page: page) }
            if let model {
                model.replaceLoader(loader)
            } else {
                model = PagedWorksModel(loader: loader)
            }
            await model?.reload()
        }
    }

    private var languageName: String {
        languageID.isEmpty ? "全部語言" : (languages.first { $0.code == languageID }?.name ?? languageID)
    }

    private static let languagesKey = "ao3.languages"

    private static func cachedLanguages() -> [AO3Language] {
        UserDefaults.standard.data(forKey: languagesKey)
            .flatMap { try? JSONDecoder().decode([AO3Language].self, from: $0) } ?? AO3Language.fallback
    }
}

/// 語言選擇（可搜尋），選項與 AO3 搜尋表單相同。
struct LanguagePickerSheet: View {
    let languages: [AO3Language]
    @Binding var selection: String
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
                if search.isEmpty {
                    row(code: "", name: "全部語言")
                }
                ForEach(filtered) { language in
                    row(code: language.code, name: language.name)
                }
            }
            .searchable(text: $search, prompt: "搜尋語言")
            .navigationTitle("作品語言")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(code: String, name: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selection == code { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
