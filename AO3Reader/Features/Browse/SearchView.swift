// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 搜尋分頁，對應官網的四種搜尋：作品（Work Search）、標籤（Tag Search）、用戶（People Search）與合集（Collections）。
///
/// - 四個範圍共用搜尋框，各自保留上一次的結果；切換範圍時只有搜尋詞改變才重新搜尋。
/// - 清空搜尋框（或按取消）時四個範圍的結果一起清空，顯示各範圍的搜尋紀錄。
/// - 作品的詳細搜尋在左上角，已套用的條件以膠囊顯示在頂部，可逐一移除。
/// - 標籤可依類型（原作、角色、配對、其他）搜尋；輸入標籤或用戶名稱時即時顯示 AO3 的建議，點選直接進入作品列表。
struct SearchView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case works, tags, people, collections
        var id: String { rawValue }
        var title: String {
            switch self {
            case .works: String(localized: "作品")
            case .tags: String(localized: "標籤")
            case .people: String(localized: "用戶")
            case .collections: String(localized: "合集")
            }
        }
    }

    /// 輸入時的建議（標籤或用戶）
    private struct Suggestion: Identifiable, Hashable {
        let title: String
        let route: WorkListRoute
        var id: String { route.path + route.baseQuery.description + title }
    }

    @Environment(AppState.self) private var app
    @Environment(\.openWorkList) private var openWorkList
    @State private var scope: Scope = .works
    @State private var text = ""
    /// 作品的詳細搜尋條件（關鍵字以搜尋框為準）
    @State private var query = WorkSearchQuery()
    @State private var tagType: TagSearchType = .any
    @State private var showsFilters = false
    /// 各範圍上一次搜尋的關鍵字（切換範圍時判斷是否需要重新搜尋）
    @State private var searched: [Scope: String] = [:]
    @State private var suggestions: [Suggestion] = []
    @State private var lookup: Task<Void, Never>?

    @State private var works: PagedWorksModel?
    @State private var tags: PagedListModel<TagResult>?
    @State private var people: PagedListModel<PersonResult>?
    @State private var collections: PagedListModel<CollectionResult>?

    var body: some View {
        content
            .navigationTitle("搜尋")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $text, prompt: Text(prompt))
            // 輸入時也保留標題與左上角的詳細搜尋（預設會隱藏導覽列）
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .searchSuggestions {
                ForEach(suggestions) { suggestion in
                    Button {
                        open(suggestion)
                    } label: {
                        Label(suggestion.title, systemImage: scope == .people ? "person" : "tag")
                    }
                }
            }
            .onSubmit(of: .search) { submit() }
            .onChange(of: text) {
                if text.isEmpty {
                    clearAll()
                } else {
                    scheduleSuggestions()
                }
            }
            .onChange(of: scope) {
                suggestions = []
                // 只有這個範圍還沒用目前的關鍵字搜尋過時才重新搜尋
                if !text.isEmpty, searched[scope] != text { submit() }
            }
            .onChange(of: tagType) { if scope == .tags, !text.isEmpty { submit() } }
            .safeAreaBar(edge: .top) { topBar }
            .toolbar {
                // 詳細搜尋（作品的條件）任何範圍都可打開，送出時切到作品範圍
                ToolbarItem(placement: .topBarLeading) {
                    Button("詳細搜尋", systemImage: query.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                        showsFilters = true
                    }
                }
            }
            .sheet(isPresented: $showsFilters) {
                FilterSheet(query: $query, mode: .search) {
                    showsFilters = false
                    if scope != .works { scope = .works }
                    submitWorks()
                }
                .presentationDetents([.medium, .large])
            }
    }

    // MARK: 頂部

    /// 搜尋範圍；標籤範圍下方是標籤類型，作品範圍下方是已套用的詳細搜尋條件
    private var topBar: some View {
        VStack(spacing: 8) {
            Picker("搜尋範圍", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if scope == .tags {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(TagSearchType.allCases) { type in
                            chip(type.title, selected: tagType == type) { tagType = type }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else if scope == .works, !conditions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(conditions) { condition in
                            Button {
                                condition.remove(&query)
                                submitWorks()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(condition.label).lineLimit(1)
                                    Image(systemName: "xmark").imageScale(.small)
                                }
                                .appFont(.footnote)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if selected {
                Button(title, action: action).buttonStyle(.glassProminent)
            } else {
                Button(title, action: action).buttonStyle(.glass)
            }
        }
        .appFont(.footnote)
    }

    /// 已套用的詳細搜尋條件
    private var conditions: [SearchCondition] {
        SearchCondition.list(for: query, translate: { app.tags.translation(for: $0) ?? $0 })
    }

    private var prompt: String {
        switch scope {
        case .works: String(localized: "標題、作者、標籤、關鍵字")
        case .tags: String(localized: "標籤名稱")
        case .people: String(localized: "用戶名稱")
        case .collections: String(localized: "合集標題")
        }
    }

    // MARK: 內容

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .works:
            if let works { WorkListView(model: works) } else { history("搜尋作品", "輸入關鍵字，或點左上角使用官網的詳細搜尋") }
        case .tags:
            if let tags {
                PagedListView(model: tags) { tag in
                    NavigationLink(value: WorkListRoute.tag(name: tag.name, path: tag.path)) { TagRow(tag: tag) }
                }
            } else {
                history("搜尋標籤", "找到標籤後可查看該標籤下的所有作品，並再加入其他條件篩選")
            }
        case .people:
            if let people {
                PagedListView(model: people) { person in
                    NavigationLink(value: WorkListRoute.person(name: person.name, path: person.path)) { PersonRow(person: person) }
                }
            } else {
                history("搜尋用戶", "輸入作者名稱或 pseud")
            }
        case .collections:
            if let collections {
                PagedListView(model: collections) { collection in
                    NavigationLink(value: WorkListRoute.collection(collection)) { CollectionRow(collection: collection) }
                }
            } else {
                history("搜尋合集", "輸入合集標題；不輸入直接按搜尋可瀏覽全部合集")
            }
        }
    }

    /// 還沒有結果時顯示這個範圍的搜尋紀錄
    @ViewBuilder
    private func history(_ title: LocalizedStringKey, _ message: LocalizedStringKey) -> some View {
        let terms = app.searchHistory.terms(for: scope.rawValue)
        if terms.isEmpty {
            ContentUnavailableView(title, systemImage: "magnifyingglass", description: Text(message))
        } else {
            List {
                Section {
                    ForEach(terms, id: \.self) { term in
                        Button {
                            text = term
                            submit()
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button("刪除", systemImage: "trash", role: .destructive) {
                                app.searchHistory.remove(term, scope: scope.rawValue)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("最近搜尋")
                        Spacer()
                        Button("清除") { app.searchHistory.clear(scope: scope.rawValue) }
                            .textCase(nil)
                    }
                } footer: {
                    Text(message)
                }
            }
        }
    }

    // MARK: 搜尋

    private func submit() {
        let client = app.client
        let term = text.trimmingCharacters(in: .whitespaces)
        suggestions = []
        switch scope {
        case .works:
            submitWorks()
            return
        case .tags:
            guard !term.isEmpty else { return }
            let type = tagType
            let model = PagedListModel<TagResult> { page in try await client.searchTags(name: term, type: type, page: page) }
            tags = model
            Task { await model.reload() }
        case .people:
            guard !term.isEmpty else { return }
            let model = PagedListModel<PersonResult> { page in try await client.searchPeople(name: term, page: page) }
            people = model
            Task { await model.reload() }
        case .collections:
            let model = PagedListModel<CollectionResult> { page in try await client.searchCollections(title: term, page: page) }
            collections = model
            Task { await model.reload() }
        }
        searched[scope] = text
        app.searchHistory.add(term, scope: scope.rawValue)
    }

    /// 作品搜尋：關鍵字取自搜尋框，其他條件取自詳細搜尋
    private func submitWorks() {
        let term = text.trimmingCharacters(in: .whitespaces)
        var snapshot = query
        snapshot.query = term
        guard !term.isEmpty || !query.isEmpty else {
            works = nil
            return
        }
        let client = app.client
        let search = snapshot
        let model = PagedWorksModel { page in try await client.searchWorks(search, page: page) }
        works = model
        Task { await model.reload() }
        searched[.works] = text
        app.searchHistory.add(term, scope: Scope.works.rawValue)
    }

    /// 清空搜尋框：四個範圍的結果一起清空
    private func clearAll() {
        works = nil
        tags = nil
        people = nil
        collections = nil
        searched = [:]
        suggestions = []
        lookup?.cancel()
    }

    // MARK: 建議

    private func scheduleSuggestions() {
        lookup?.cancel()
        let term = text.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2, scope == .tags || scope == .people else {
            suggestions = []
            return
        }
        let client = app.client
        let scope = scope
        let kind: AutocompleteKind = switch tagType {
        case .any: .tag
        case .fandom: .fandom
        case .character: .character
        case .relationship: .relationship
        case .freeform: .freeform
        }
        lookup = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if scope == .people {
                let names = (try? await client.autocomplete(.pseud, term: term)) ?? []
                guard !Task.isCancelled else { return }
                // 以帳號為單位顯示（同一位作者的多個 pseud 只列一次），避免 pseud 名稱看起來像標籤
                var seen: Set<String> = []
                suggestions = names.compactMap { name -> Suggestion? in
                    let user = Self.splitPseud(name).user
                    guard seen.insert(user.lowercased()).inserted else { return nil }
                    return Suggestion(title: user, route: .person(name: user, path: "/users/\(user)"))
                }
                .prefix(8).map { $0 }
            } else {
                let names = (try? await client.autocomplete(kind, term: term)) ?? []
                guard !Task.isCancelled else { return }
                suggestions = names.prefix(8).map { Suggestion(title: $0, route: .tag(name: $0)) }
            }
        }
    }

    /// 點選建議：直接進入作品列表，並記入搜尋紀錄
    private func open(_ suggestion: Suggestion) {
        app.searchHistory.add(suggestion.route.title, scope: scope.rawValue)
        suggestions = []
        openWorkList(suggestion.route)
    }

    /// AO3 的 pseud 建議格式為「pseud (user)」，pseud 與用戶同名時只有名稱
    private static func splitPseud(_ name: String) -> (pseud: String, user: String) {
        guard let match = name.wholeMatch(of: /(.+) \((.+)\)/) else { return (name, name) }
        return (String(match.1), String(match.2))
    }
}

/// 已套用的詳細搜尋條件（頂部的膠囊，點擊移除）
struct SearchCondition: Identifiable {
    let id: String
    let label: String
    let remove: (inout WorkSearchQuery) -> Void

    @MainActor
    static func list(for query: WorkSearchQuery, translate: (String) -> String) -> [SearchCondition] {
        var result: [SearchCondition] = []
        func add(_ id: String, _ label: String, _ remove: @escaping (inout WorkSearchQuery) -> Void) {
            result.append(SearchCondition(id: id, label: label, remove: remove))
        }
        // 鍵路徑需為 Sendable 才能放進移除條件的閉包
        func text(_ id: String, _ title: String, _ keyPath: WritableKeyPath<WorkSearchQuery, String> & Sendable) {
            let value = query[keyPath: keyPath].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { add(id, "\(title) \(value)") { $0[keyPath: keyPath] = "" } }
        }
        func tags(_ id: String, _ keyPath: WritableKeyPath<WorkSearchQuery, String> & Sendable, prefix: String = "") {
            let names = query[keyPath: keyPath].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for name in names {
                add("\(id):\(name)", prefix + name) { query in
                    query[keyPath: keyPath] = query[keyPath: keyPath].split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && $0 != name }
                        .joined(separator: ",")
                }
            }
        }
        text("title", String(localized: "標題"), \.title)
        text("creators", String(localized: "作者"), \.creators)
        text("revised", String(localized: "更新時間"), \.revisedAt)
        text("words", String(localized: "字數"), \.wordCount)
        if let rating = query.rating { add("rating", translate(rating.title)) { $0.rating = nil } }
        for warning in query.warnings.sorted(by: { $0.rawValue < $1.rawValue }) {
            add("warning:\(warning.rawValue)", translate(warning.title)) { $0.warnings.remove(warning) }
        }
        for category in query.categories.sorted(by: { $0.rawValue < $1.rawValue }) {
            add("category:\(category.rawValue)", translate(category.title)) { $0.categories.remove(category) }
        }
        switch query.completion {
        case .yes: add("complete", String(localized: "僅完結")) { $0.completion = .any }
        case .no: add("complete", String(localized: "僅連載")) { $0.completion = .any }
        case .any: break
        }
        switch query.crossover {
        case .yes: add("crossover", String(localized: "僅 Crossover")) { $0.crossover = .any }
        case .no: add("crossover", String(localized: "排除 Crossover")) { $0.crossover = .any }
        case .any: break
        }
        if query.singleChapter { add("single", String(localized: "僅單章作品")) { $0.singleChapter = false } }
        if !query.languageID.isEmpty {
            add("language", AO3LanguagePickerPage.name(for: query.languageID)) { $0.languageID = "" }
        }
        tags("fandom", \.fandomNames)
        tags("character", \.characterNames)
        tags("relationship", \.relationshipNames)
        tags("freeform", \.freeformNames)
        tags("excluded", \.excludedTagNames, prefix: String(localized: "排除 "))
        text("hits", String(localized: "點擊數"), \.hits)
        text("kudos", "Kudos", \.kudosCount)
        text("comments", String(localized: "評論數"), \.commentsCount)
        text("bookmarks", String(localized: "書籤數"), \.bookmarksCount)
        return result
    }
}

private struct TagRow: View {
    let tag: TagResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tag.name).appFont(.headline)
                if tag.isCanonical {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("正式標籤")
                }
            }
            HStack(spacing: 8) {
                if !tag.type.isEmpty { Text(tag.type) }
                if let uses = tag.uses { Label(uses, systemImage: "doc.text").labelStyle(.titleAndIcon) }
            }
            .appFont(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct PersonRow: View {
    let person: PersonResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(person.name, systemImage: "person.crop.circle").appFont(.headline)
            if let detail = person.detail, !detail.isEmpty {
                Text(detail).appFont(.caption).foregroundStyle(.secondary)
            }
            if let summary = person.summary, !summary.isEmpty {
                Text(summary).appFont(.callout).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CollectionRow: View {
    let collection: CollectionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(collection.title).appFont(.headline)
            HStack(spacing: 6) {
                if !collection.name.isEmpty { Text(collection.name) }
                if !collection.maintainers.isEmpty { Text("· " + collection.maintainers.joined(separator: ", ")) }
            }
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if !collection.summary.isEmpty {
                Text(collection.summary).appFont(.callout).lineLimit(3)
            }
            if let updated = collection.updated {
                Text(updated).appFont(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
