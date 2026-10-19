import SwiftUI

/// 篩選表單，有兩種模式：
/// - `.search`：對應官網「Work Search」（/works/search）全部欄位
/// - `.filter`：對應標籤 / 合集作品頁右側的「Sort and Filter」（可包含 / 排除標籤）
/// 標籤欄位以 AO3 自動完成查找正式標籤後填入；數值欄位沿用官網語法（如 "> 1000"、"< 7 days"）。
struct FilterSheet: View {
    enum Mode { case search, filter }

    @Binding var query: WorkSearchQuery
    var mode: Mode = .search
    var onSearch: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("作品資訊") {
                    TextField(mode == .search ? "關鍵字" : "在結果中搜尋", text: $query.query)
                    if mode == .search {
                        TextField("標題", text: $query.title)
                        TextField("作者 / 創作者", text: $query.creators)
                        TextField("更新時間（如 < 7 days）", text: $query.revisedAt)
                    }
                    triStatePicker("完結狀態", selection: $query.completion, yes: "僅完結", no: "僅連載")
                    triStatePicker("Crossover", selection: $query.crossover, yes: "僅 Crossover", no: "排除 Crossover")
                    if mode == .search {
                        Toggle("僅單章作品", isOn: $query.singleChapter)
                        TextField("字數（如 > 10000、1000-5000）", text: $query.wordCount)
                    } else {
                        TextField("最少字數", text: $query.wordsFrom).keyboardType(.numberPad)
                        TextField("最多字數", text: $query.wordsTo).keyboardType(.numberPad)
                    }
                    TextField("語言代碼（如 en、zh、ja）", text: $query.languageID)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    TagTokenField(title: "Fandoms", text: $query.fandomNames, kind: .fandom)
                    TagTokenField(title: "角色", text: $query.characterNames, kind: .character)
                    TagTokenField(title: "配對 / 關係", text: $query.relationshipNames, kind: .relationship)
                    TagTokenField(title: "其他標籤", text: $query.freeformNames, kind: .freeform)
                    if mode == .filter {
                        TagTokenField(title: "排除標籤", text: $query.excludedTagNames, kind: .tag)
                    }
                    Picker("分級", selection: $query.rating) {
                        Text("不限").tag(WorkSearchQuery.Rating?.none)
                        ForEach(WorkSearchQuery.Rating.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                } header: {
                    Text(mode == .search ? "作品標籤" : "包含 / 排除標籤")
                } footer: {
                    Text("輸入至少兩個字會向 AO3 查找匹配的標籤，點選即可加入。")
                }

                Section("Archive Warnings") {
                    ForEach(WorkSearchQuery.ArchiveWarning.allCases) { warning in
                        Toggle(warning.title, isOn: membership(warning, in: $query.warnings))
                    }
                }

                Section("分類") {
                    ForEach(WorkSearchQuery.Category.allCases) { category in
                        Toggle(category.title, isOn: membership(category, in: $query.categories))
                    }
                }

                if mode == .search {
                    Section("作品統計") {
                        TextField("點擊數", text: $query.hits)
                        TextField("Kudos", text: $query.kudosCount)
                        TextField("評論數", text: $query.commentsCount)
                        TextField("書籤數", text: $query.bookmarksCount)
                    }
                    .keyboardType(.numbersAndPunctuation)
                }

                Section("排序") {
                    Picker("排序依據", selection: $query.sortColumn) {
                        ForEach(WorkSearchQuery.SortColumn.allCases.filter { mode == .search || $0 != .bestMatch }) {
                            Text($0.title).tag($0)
                        }
                    }
                    if mode == .search {
                        Picker("方向", selection: $query.sortDirection) {
                            ForEach(WorkSearchQuery.SortDirection.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(mode == .search ? "進階搜尋" : "篩選作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重設", role: .destructive) {
                        query = mode == .search ? WorkSearchQuery() : WorkSearchQuery(sortColumn: .dateUpdated)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .search ? "搜尋" : "套用", action: onSearch)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func triStatePicker(_ title: LocalizedStringKey, selection: Binding<WorkSearchQuery.TriState>, yes: LocalizedStringKey, no: LocalizedStringKey) -> some View {
        Picker(title, selection: selection) {
            Text("不限").tag(WorkSearchQuery.TriState.any)
            Text(yes).tag(WorkSearchQuery.TriState.yes)
            Text(no).tag(WorkSearchQuery.TriState.no)
        }
    }

    private func membership<T: Hashable>(_ element: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding {
            set.wrappedValue.contains(element)
        } set: { isOn in
            if isOn { set.wrappedValue.insert(element) } else { set.wrappedValue.remove(element) }
        }
    }
}
