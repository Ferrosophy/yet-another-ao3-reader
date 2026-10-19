import SwiftUI

/// 與 AO3 官網「Work Search」頁面欄位一一對應的篩選表單。
/// 數值欄位沿用官網語法（如 "> 1000"、"100-500"、"< 7 days"），不在客戶端二次轉換。
struct FilterSheet: View {
    @Binding var query: WorkSearchQuery
    var onSearch: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("作品資訊") {
                    TextField("關鍵字", text: $query.query)
                    TextField("標題", text: $query.title)
                    TextField("作者 / 創作者", text: $query.creators)
                    TextField("更新時間（如 < 7 days）", text: $query.revisedAt)
                    triStatePicker("完結狀態", selection: $query.completion, yes: "僅完結", no: "僅連載")
                    triStatePicker("Crossover", selection: $query.crossover, yes: "僅 Crossover", no: "排除 Crossover")
                    Toggle("僅單章作品", isOn: $query.singleChapter)
                    TextField("字數（如 > 10000、1000-5000）", text: $query.wordCount)
                    TextField("語言代碼（如 en、zh、ja）", text: $query.languageID)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    TextField("Fandoms", text: $query.fandomNames)
                    Picker("分級", selection: $query.rating) {
                        Text("不限").tag(WorkSearchQuery.Rating?.none)
                        ForEach(WorkSearchQuery.Rating.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    TextField("角色", text: $query.characterNames)
                    TextField("配對 / 關係", text: $query.relationshipNames)
                    TextField("其他標籤", text: $query.freeformNames)
                } header: {
                    Text("作品標籤")
                } footer: {
                    Text("多個標籤以逗號分隔，與官網相同。")
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

                Section("作品統計") {
                    TextField("點擊數", text: $query.hits)
                    TextField("Kudos", text: $query.kudosCount)
                    TextField("評論數", text: $query.commentsCount)
                    TextField("書籤數", text: $query.bookmarksCount)
                }
                .keyboardType(.numbersAndPunctuation)

                Section("排序") {
                    Picker("排序依據", selection: $query.sortColumn) {
                        ForEach(WorkSearchQuery.SortColumn.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("方向", selection: $query.sortDirection) {
                        ForEach(WorkSearchQuery.SortDirection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("進階搜尋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重設", role: .destructive) { query = WorkSearchQuery() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("搜尋", action: onSearch)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func triStatePicker(_ title: String, selection: Binding<WorkSearchQuery.TriState>, yes: String, no: String) -> some View {
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
