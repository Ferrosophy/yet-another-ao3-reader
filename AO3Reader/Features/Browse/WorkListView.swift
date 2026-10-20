import UIKit
import SwiftUI

/// 作品卡片列表，捲到底自動載入下一頁。
struct WorkListView: View {
    let model: PagedWorksModel
    /// 列表頂部、跟著內容一起捲動的區塊（例如首頁的榜單切換）
    var header: AnyView?

    var body: some View {
        List {
            if let header {
                header
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

/// 卡片上單一欄位（作品名稱或簡介）的沉浸式譯文。只觀察自己的翻譯狀態，
/// 出現時排入翻譯、離開畫面時取消尚未送出的請求。
struct CardTranslationView: View {
    let key: String
    let text: String
    let font: Font.TextStyle
    /// nil 為不限行數
    let lineLimit: Int?
    @Environment(AppState.self) private var app

    var body: some View {
        let slot = app.summaries.slot(key)
        Group {
            switch slot.value {
            case .done(let translated):
                Text(translated)
                    .appFont(font)
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.tint.opacity(0.55)).frame(width: 3)
                    }
            case .failed(let message):
                Button {
                    app.summaries.retry(key, text: text)
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
        .task(id: app.summaries.currentSignature) { app.summaries.request(key, text: text) }
        .onDisappear { app.summaries.cancel(key) }
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
            Label("翻譯作品資訊", systemImage: "translate")
        }
        .toggleStyle(.button)
    }
}

struct WorkRow: View {
    let work: WorkSummary
    /// 是否翻譯這張卡片（瀏覽頁只翻譯目前顯示的卡片）
    var translationActive = true
    /// 列表中簡介只顯示前 3 行；瀏覽頁的大卡片顯示完整簡介
    var compact = true
    @Environment(AppState.self) private var app
    @AppStorage(TranslationVisibility.titleKey) private var showsTitleTranslation = true
    @AppStorage(TranslationVisibility.fandomKey) private var showsFandomTranslation = true
    @AppStorage(TranslationVisibility.tagsKey) private var showsTagTranslation = true
    @AppStorage(TranslationVisibility.summaryKey) private var showsSummaryTranslation = true
    /// 簡介原文實際顯示的行數（最多 3 行），譯文顯示相同行數
    @State private var summaryLines = 3

    private static let summaryLineHeight = UIFont.preferredFont(forTextStyle: .callout).lineHeight

    private var translates: Bool { app.summaries.isEnabled && translationActive }

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
            if translates, showsTitleTranslation {
                CardTranslationView(key: SummaryTranslator.titleKey(work.id), text: work.title,
                                    font: .subheadline, lineLimit: 2)
            }
            if !work.authors.isEmpty {
                Text(work.authors.joined(separator: ", "))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // 標籤過長時換行完整顯示，不截斷
            if !work.fandoms.isEmpty {
                let translatesFandoms = translates && showsFandomTranslation
                Text(work.fandoms.joined(separator: " · "))
                    .appFont(.caption)
                    .foregroundStyle(.tint)
                    .task(id: translatesFandoms) { if translatesFandoms { app.tags.request(work.fandoms) } }
                if translatesFandoms { tagTranslation(work.fandoms) }
            }
            let tags = work.relationships + work.characters.prefix(3) + work.freeforms.prefix(4)
            if !tags.isEmpty {
                let translatesTags = translates && showsTagTranslation
                Text(tags.joined(separator: " · "))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .task(id: translatesTags) { if translatesTags { app.tags.request(tags) } }
                if translatesTags { tagTranslation(tags) }
            }
            if !work.summary.isEmpty {
                // 卡片只顯示前 3 行；翻譯使用完整簡介，再以與原文相同的行數顯示
                Text(work.summary)
                    .appFont(.callout)
                    .lineLimit(compact ? 3 : nil)
                    .onGeometryChange(for: Int.self, of: {
                        min(max(Int(($0.size.height / Self.summaryLineHeight).rounded()), 1), 3)
                    }) { summaryLines = $0 }
                if translates, showsSummaryTranslation {
                    CardTranslationView(key: SummaryTranslator.summaryKey(work.id), text: work.summary,
                                        font: .callout, lineLimit: compact ? summaryLines : nil)
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

    /// 標籤譯文（目標語言跟隨介面語言），顯示在原標籤下方
    @ViewBuilder
    private func tagTranslation(_ tags: [String]) -> some View {
        if tags.contains(where: { app.tags.translation(for: $0) != nil }) {
            Text(tags.map { app.tags.translation(for: $0) ?? $0 }.joined(separator: " · "))
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Capsule().fill(.tint.opacity(0.4)).frame(width: 2)
                }
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
