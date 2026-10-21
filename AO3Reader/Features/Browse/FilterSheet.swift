// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 篩選表單。兩種模式欄位完全相同（作品列表的篩選與詳細搜尋一致）：
/// - `.search`：搜尋頁的詳細搜尋，關鍵字由搜尋框輸入
/// - `.filter`：標籤 / 用戶 / 系列 / 合集作品列表的篩選，多一個「在結果中搜尋」
/// 標籤欄位以 AO3 自動完成查找正式標籤後填入；數值欄位沿用官網語法（如 "> 1000"、"< 7 days"）。
struct FilterSheet: View {
    enum Mode { case search, filter }

    @Binding var query: WorkSearchQuery
    var mode: Mode = .search
    var onSearch: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            Form {
                Section("作品資訊") {
                    if mode == .filter {
                        TextField("在結果中搜尋", text: $query.query)
                    }
                    TextField("標題", text: $query.title)
                    TextField("作者 / 創作者", text: $query.creators)
                    ComparisonField(title: "更新時間", value: $query.revisedAt, units: ComparisonField.timeUnits)
                    triStatePicker("完結狀態", selection: $query.completion, yes: "僅完結", no: "僅連載")
                    triStatePicker("Crossover", selection: $query.crossover, yes: "僅 Crossover", no: "排除 Crossover")
                    Toggle("僅單章作品", isOn: $query.singleChapter)
                    ComparisonField(title: "字數", value: $query.wordCount)
                    NavigationLink {
                        AO3LanguagePickerPage(selection: $query.languageID)
                    } label: {
                        LabeledContent("語言", value: AO3LanguagePickerPage.name(for: query.languageID))
                    }
                }

                Section {
                    TagTokenField(title: "原作", text: $query.fandomNames, kind: .fandom)
                    TagTokenField(title: "角色", text: $query.characterNames, kind: .character)
                    TagTokenField(title: "配對 / 關係", text: $query.relationshipNames, kind: .relationship)
                    TagTokenField(title: "其他標籤", text: $query.freeformNames, kind: .freeform)
                    TagTokenField(title: "排除標籤", text: $query.excludedTagNames, kind: .tag)
                    Picker("分級", selection: $query.rating) {
                        Text("不限").tag(WorkSearchQuery.Rating?.none)
                        ForEach(WorkSearchQuery.Rating.allCases) {
                            Text(app.tags.translation(for: $0.title) ?? $0.title).tag(Optional($0))
                        }
                    }
                    .tint(.primary)
                } header: {
                    Text("作品標籤")
                } footer: {
                    Text("輸入至少兩個字會向 AO3 查找匹配的標籤，點選即可加入。")
                }

                // 警告與分類譯成介面語言（內建固定標籤翻譯），下方保留 AO3 原文
                Section {
                    ForEach(WorkSearchQuery.ArchiveWarning.allCases) { warning in
                        Toggle(isOn: membership(warning, in: $query.warnings)) { fixedTagLabel(warning.title) }
                    }
                } header: {
                    AO3TermLabel(title: "警告", english: "Archive Warnings")
                }

                Section {
                    ForEach(WorkSearchQuery.Category.allCases) { category in
                        Toggle(isOn: membership(category, in: $query.categories)) { fixedTagLabel(category.title) }
                    }
                } header: {
                    AO3TermLabel(title: "分類", english: "Category")
                }

                Section("作品統計") {
                    ComparisonField(title: "點擊數", value: $query.hits)
                    ComparisonField(title: "Kudos", value: $query.kudosCount)
                    ComparisonField(title: "評論數", value: $query.commentsCount)
                    ComparisonField(title: "書籤數", value: $query.bookmarksCount)
                }

                Section("排序") {
                    Picker("排序依據", selection: $query.sortColumn) {
                        ForEach(WorkSearchQuery.SortColumn.allCases.filter { mode == .search || $0 != .bestMatch }) {
                            Text($0.title).tag($0)
                        }
                    }
                    .tint(.primary)
                    Picker("方向", selection: $query.sortDirection) {
                        ForEach(WorkSearchQuery.SortDirection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(mode == .search ? "詳細搜尋" : "詳細篩選")
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

    /// 固定標籤：介面語言的譯名，下方以小字附上 AO3 原文
    @ViewBuilder
    private func fixedTagLabel(_ title: String) -> some View {
        if let translated = app.tags.translation(for: title) {
            VStack(alignment: .leading, spacing: 2) {
                Text(translated)
                Text(verbatim: title).appFont(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(verbatim: title)
        }
    }

    private func triStatePicker(_ title: LocalizedStringKey, selection: Binding<WorkSearchQuery.TriState>, yes: LocalizedStringKey, no: LocalizedStringKey) -> some View {
        Picker(title, selection: selection) {
            Text("不限").tag(WorkSearchQuery.TriState.any)
            Text(yes).tag(WorkSearchQuery.TriState.yes)
            Text(no).tag(WorkSearchQuery.TriState.no)
        }
        // 選單的值一律使用一般文字色，不跟隨主題色
        .tint(.primary)
    }

    private func membership<T: Hashable>(_ element: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding {
            set.wrappedValue.contains(element)
        } set: { isOn in
            if isOn { set.wrappedValue.insert(element) } else { set.wrappedValue.remove(element) }
        }
    }
}

/// 「大於 / 小於」加數值（可選單位）的篩選欄位，組成官網語法，例如「> 10000」「< 7 days」。
struct ComparisonField: View {
    struct Unit: Hashable {
        let value: String
        let title: LocalizedStringKey
        static func == (lhs: Unit, rhs: Unit) -> Bool { lhs.value == rhs.value }
        func hash(into hasher: inout Hasher) { hasher.combine(value) }
    }

    static let timeUnits: [Unit] = [
        Unit(value: "days", title: "天"),
        Unit(value: "weeks", title: "週"),
        Unit(value: "months", title: "月"),
        Unit(value: "years", title: "年"),
    ]

    let title: LocalizedStringKey
    @Binding var value: String
    var units: [Unit] = []

    @State private var comparator = ">"
    @State private var number = ""
    @State private var unit = "days"

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 8)
            Picker("", selection: $comparator) {
                Text(verbatim: ">").tag(">")
                Text(verbatim: "<").tag("<")
            }
            .pickerStyle(.segmented)
            .fixedSize()
            TextField("數值", text: $number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            if !units.isEmpty {
                Picker("", selection: $unit) {
                    ForEach(units, id: \.value) { Text($0.title).tag($0.value) }
                }
                .labelsHidden()
                .fixedSize()
                .tint(.primary)
            }
        }
        .onAppear(perform: parse)
        .onChange(of: comparator) { compose() }
        .onChange(of: number) { compose() }
        .onChange(of: unit) { compose() }
        .onChange(of: value) { if value.isEmpty, !number.isEmpty { number = "" } }
    }

    /// 讀回已有的條件（例如「< 7 days」）
    private func parse() {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<") { comparator = "<" } else if trimmed.hasPrefix(">") { comparator = ">" }
        number = trimmed.filter(\.isNumber)
        if let match = units.first(where: { trimmed.contains($0.value.dropLast()) }) { unit = match.value }
    }

    private func compose() {
        let digits = number.filter(\.isNumber)
        guard !digits.isEmpty else {
            value = ""
            return
        }
        value = units.isEmpty ? "\(comparator) \(digits)" : "\(comparator) \(digits) \(unit)"
    }
}

/// 作品語言選擇：AO3 官網支援的全部語言，可搜尋；選擇後返回。
struct AO3LanguagePickerPage: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var languages: [AO3Language] { LatestWorksView.cachedLanguages() }

    static func name(for code: String) -> String {
        guard !code.isEmpty else { return String(localized: "全部語言") }
        return LatestWorksView.cachedLanguages().first { $0.code == code }?.name ?? code
    }

    private var filtered: [AO3Language] {
        guard !search.isEmpty else { return languages }
        return languages.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if search.isEmpty { row(code: "", name: String(localized: "全部語言")) }
            ForEach(filtered) { language in row(code: language.code, name: language.name) }
        }
        .searchable(text: $search, prompt: "搜尋語言")
        .navigationTitle("語言")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(code: String, name: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                Text(verbatim: name).foregroundStyle(.primary)
                Spacer()
                if selection == code { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
