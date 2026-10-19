import SwiftUI

/// 作品卡片列表，捲到底自動載入下一頁。
struct WorkListView: View {
    let model: PagedWorksModel

    var body: some View {
        List {
            if let heading = model.heading {
                Text(heading)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.works) { work in
                NavigationLink(value: WorkRoute(id: work.id, title: work.title)) {
                    WorkRow(work: work)
                }
                .task { await model.loadMoreIfNeeded(current: work) }
            }
            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
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
            } else if model.hasLoaded, !model.isLoading, model.works.isEmpty {
                ContentUnavailableView("沒有作品", systemImage: "books.vertical")
            }
        }
        .refreshable { await model.reload() }
    }
}

struct WorkRow: View {
    let work: WorkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(work.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let rating = work.rating {
                    RatingBadge(rating: rating)
                }
            }
            if !work.authors.isEmpty {
                Text(work.authors.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !work.fandoms.isEmpty {
                Text(work.fandoms.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
            let tags = work.relationships + work.characters.prefix(3) + work.freeforms.prefix(4)
            if !tags.isEmpty {
                Text(tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.callout)
                    .lineLimit(3)
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
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
            .font(.caption.bold())
            .frame(width: 24, height: 24)
            .glassEffect(.regular.tint(color.opacity(0.6)), in: .rect(cornerRadius: 6))
            .accessibilityLabel(rating)
    }
}

/// 由左至右排列子視圖，超出寬度時整個項目換到下一行。
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
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            guard size.width > 0 else { continue }  // 空的 stat（值為 nil）不佔位
            let needed = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
