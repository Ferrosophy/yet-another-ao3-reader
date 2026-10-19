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
            HStack(spacing: 12) {
                stat(work.language, "globe")
                stat(work.words, "text.word.spacing")
                stat(work.chapters, "list.number")
                stat(work.kudos, "heart")
                stat(work.hits, "eye")
                Spacer()
                if let updated = work.updated {
                    Text(updated)
                }
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
