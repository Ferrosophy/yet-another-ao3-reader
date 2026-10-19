import SwiftUI

/// 作品卡片列表，捲到底自動載入下一頁。
struct WorkListView: View {
    let model: PagedWorksModel
    /// 是否顯示 AO3 的結果數標題（如 "1 - 20 of 12,345 Works"）
    var showsHeading = true
    /// 列表頂部、跟著內容一起捲動的區塊（例如首頁的榜單切換）
    var header: AnyView?

    var body: some View {
        List {
            if let header {
                header
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if showsHeading, let heading = model.heading {
                Text(heading)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(model.works) { work in
                    NavigationLink(value: WorkRoute(id: work.id, title: work.title)) {
                        WorkRow(work: work)
                    }
                    .contextMenu {
                        BookshelfMenuButton(work: work)
                    }
                    .task { await model.loadMoreIfNeeded(current: work) }
                }
            }
            .listSectionSeparator(.hidden)
            // 第一頁載入時由下方 overlay 顯示大圖示，這裡只在載入下一頁時顯示
            if model.isLoading, !model.works.isEmpty {
                AO3LoadingView(compact: true)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .overlay {
            if let error = model.error, model.works.isEmpty {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重試") { Task { await model.reload() } }
                        .buttonStyle(.glassProminent)
                }
            } else if model.isLoading, model.works.isEmpty {
                AO3LoadingView()
            } else if model.hasLoaded, !model.isLoading, model.works.isEmpty {
                ContentUnavailableView("沒有作品", systemImage: "books.vertical")
            }
        }
        .refreshable { await model.reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SummaryTranslationToggle()
            }
        }
    }
}

/// 長按作品卡片：加入或移出書架
struct BookshelfMenuButton: View {
    let work: WorkSummary
    @Environment(AppState.self) private var app

    var body: some View {
        if app.bookshelf.contains(work.id) {
            Button("移出書架", systemImage: "books.vertical.fill", role: .destructive) { app.bookshelf.remove(work.id) }
        } else {
            Button("加入書架", systemImage: "books.vertical") { app.bookshelf.add(work) }
        }
    }
}

/// 作品列表的「翻譯簡介」開關（沉浸式：譯文顯示在簡介下方）。
struct SummaryTranslationToggle: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var summaries = app.summaries
        Toggle(isOn: $summaries.isEnabled) {
            Label("翻譯簡介", systemImage: "translate")
        }
        .toggleStyle(.button)
    }
}

struct WorkRow: View {
    let work: WorkSummary
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(work.title)
                    .appFont(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let rating = work.rating {
                    RatingBadge(rating: rating)
                }
            }
            if !work.authors.isEmpty {
                Text(work.authors.joined(separator: ", "))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !work.fandoms.isEmpty {
                Text(work.fandoms.joined(separator: " · "))
                    .appFont(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
            let tags = work.relationships + work.characters.prefix(3) + work.freeforms.prefix(4)
            if !tags.isEmpty {
                Text(tags.joined(separator: " · "))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !work.summary.isEmpty {
                Text(work.summary)
                    .appFont(.callout)
                    .lineLimit(3)
                if app.summaries.isEnabled {
                    summaryTranslation
                        .task(id: app.summaries.currentSignature) {
                            app.summaries.request(id: work.id, summary: work.summary)
                        }
                }
            }
            // 統計項目數量與長度不定（語言名稱可能很長），用自動換行排列，避免擠壓成直排
            FlowLayout(horizontalSpacing: 12, verticalSpacing: 4) {
                stat(work.language, "globe")
                stat(work.words, "text.word.spacing")
                stat(work.chapters, "list.number")
                stat(work.kudos, "heart")
                stat(work.hits, "eye")
                stat(work.updated, "calendar")
            }
            .appFont(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var summaryTranslation: some View {
        switch app.summaries.translation(for: work.id) {
        case .done(let text):
            Text(text)
                .appFont(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(.tint.opacity(0.55)).frame(width: 3)
                }
        case .failed(let message):
            Button {
                app.summaries.retry(id: work.id, summary: work.summary)
            } label: {
                Label("翻譯失敗：\(message)　點擊重試", systemImage: "arrow.clockwise")
                    .appFont(.caption)
                    .lineLimit(2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        case .loading, nil:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("翻譯中…")
            }
            .appFont(.caption)
            .foregroundStyle(.tertiary)
            .padding(.leading, 10)
        }
    }

    @ViewBuilder
    private func stat(_ value: String?, _ symbol: String) -> some View {
        if let value, !value.isEmpty {
            Label(value, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

struct RatingBadge: View {
    let rating: String

    private var letter: String {
        switch rating {
        case "General Audiences": "G"
        case "Teen And Up Audiences": "T"
        case "Mature": "M"
        case "Explicit": "E"
        default: "?"
        }
    }

    private var color: Color {
        switch letter {
        case "G": .green
        case "T": .yellow
        case "M": .orange
        case "E": .red
        default: .gray
        }
    }

    var body: some View {
        Text(letter)
            .appFont(.caption, weight: .bold)
            .frame(width: 24, height: 24)
            .glassEffect(.regular.tint(color.opacity(0.6)), in: .rect(cornerRadius: 6))
            .accessibilityLabel(rating)
    }
}

/// 由左至右排列子視圖，超出寬度時整個項目換到下一行；單一項目最寬不超過容器寬度。
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        let limit = ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil)
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(limit)
            if maxWidth.isFinite { size.width = min(size.width, maxWidth) }
            guard size.width > 0 else { continue }  // 空的 stat（值為 nil）不佔位
            let needed = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            current.sizes.append(size)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
