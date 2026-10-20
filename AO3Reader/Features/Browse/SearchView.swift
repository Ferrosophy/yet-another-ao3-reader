import SwiftUI

/// 搜尋分頁，對應官網的四種搜尋：作品（Work Search）、標籤（Tag Search）、用戶（People Search）與合集（Collections）。
/// 結果皆由 AO3 伺服器產生；點標籤、用戶或合集可進入其作品列表，再進一步篩選。
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

    @Environment(AppState.self) private var app
    @State private var scope: Scope = .works
    @State private var query = WorkSearchQuery()
    @State private var tagType: TagSearchType = .any
    @State private var showsFilters = false

    @State private var works: PagedWorksModel?
    @State private var tags: PagedListModel<TagResult>?
    @State private var people: PagedListModel<PersonResult>?
    @State private var collections: PagedListModel<CollectionResult>?

    var body: some View {
        content
            .navigationTitle("搜尋")
            .searchable(text: $query.query, prompt: Text(prompt))
            .searchScopes($scope) {
                ForEach(Scope.allCases) { Text($0.title).tag($0) }
            }
            .onSubmit(of: .search) { submit() }
            .onChange(of: scope) {
                // 合集可不輸入關鍵字直接瀏覽；其他範圍有關鍵字時自動重新搜尋
                if scope == .collections || !query.query.isEmpty { submit() }
            }
            .onChange(of: tagType) { if scope == .tags { submit() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { toolbarButton }
            }
            .sheet(isPresented: $showsFilters) {
                FilterSheet(query: $query, mode: .search) {
                    showsFilters = false
                    submit()
                }
                .presentationDetents([.medium, .large])
            }
    }

    private var prompt: String {
        switch scope {
        case .works: String(localized: "標題、作者、標籤、關鍵字")
        case .tags: String(localized: "標籤名稱")
        case .people: String(localized: "用戶名稱")
        case .collections: String(localized: "合集標題")
        }
    }

    @ViewBuilder
    private var toolbarButton: some View {
        switch scope {
        case .works:
            Button("篩選", systemImage: query.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                showsFilters = true
            }
        case .tags:
            Menu {
                Picker("標籤類型", selection: $tagType) {
                    ForEach(TagSearchType.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("標籤類型", systemImage: "tag")
            }
        case .people, .collections:
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .works:
            if let works { WorkListView(model: works) } else { placeholder("搜尋作品", "輸入關鍵字，或點右上角使用官網的詳細篩選") }
        case .tags:
            if let tags {
                PagedListView(model: tags) { tag in
                    NavigationLink(value: WorkListRoute.tag(name: tag.name, path: tag.path)) { TagRow(tag: tag) }
                }
            } else {
                placeholder("搜尋標籤", "找到標籤後可查看該標籤下的所有作品，並再加入其他條件篩選")
            }
        case .people:
            if let people {
                PagedListView(model: people) { person in
                    NavigationLink(value: WorkListRoute.person(name: person.name, path: person.path)) { PersonRow(person: person) }
                }
            } else {
                placeholder("搜尋用戶", "輸入作者名稱或 pseud")
            }
        case .collections:
            if let collections {
                PagedListView(model: collections) { collection in
                    NavigationLink(value: WorkListRoute.collection(collection)) { CollectionRow(collection: collection) }
                }
            } else {
                AO3LoadingView()
            }
        }
    }

    private func placeholder(_ title: LocalizedStringKey, _ message: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: "magnifyingglass", description: Text(message))
    }

    private func submit() {
        let client = app.client
        let text = query.query.trimmingCharacters(in: .whitespaces)
        switch scope {
        case .works:
            let snapshot = query
            let model = PagedWorksModel { page in try await client.searchWorks(snapshot, page: page) }
            works = model
            Task { await model.reload() }
        case .tags:
            guard !text.isEmpty else { return }
            let type = tagType
            let model = PagedListModel<TagResult> { page in try await client.searchTags(name: text, type: type, page: page) }
            tags = model
            Task { await model.reload() }
        case .people:
            guard !text.isEmpty else { return }
            let model = PagedListModel<PersonResult> { page in try await client.searchPeople(name: text, page: page) }
            people = model
            Task { await model.reload() }
        case .collections:
            let model = PagedListModel<CollectionResult> { page in try await client.searchCollections(title: text, page: page) }
            collections = model
            Task { await model.reload() }
        }
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
