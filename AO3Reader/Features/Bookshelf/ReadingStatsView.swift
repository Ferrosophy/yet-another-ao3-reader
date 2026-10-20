import SwiftUI

/// 時長管理：閱讀時長統計（依作品或標籤排列）與休息提醒設定。
struct ReadingStatsView: View {
    enum Grouping: String, CaseIterable, Identifiable {
        case works, tags
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .works ? "按作品" : "按標籤" }
    }

    @Environment(AppState.self) private var app
    @State private var period: ReadingStatsPeriod = .week
    @State private var grouping: Grouping = .works

    var body: some View {
        @Bindable var readingTime = app.readingTime
        let stats = app.readingTime.stats(for: period)
        let top = max(grouping == .works ? stats.byWork.first?.seconds ?? 0 : stats.byTag.first?.seconds ?? 0, 1)

        List {
            Section {
                Picker("期間", selection: $period) {
                    ForEach(ReadingStatsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    Text("閱讀時長").appFont(.subheadline).foregroundStyle(.secondary)
                    Text(Self.format(stats.total))
                        .appFont(.largeTitle, weight: .bold)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("休息提醒", isOn: $readingTime.reminderEnabled)
                if readingTime.reminderEnabled {
                    Stepper(value: $readingTime.reminderMinutes, in: 5...240, step: 5) {
                        LabeledContent("連續閱讀", value: String(localized: "\(readingTime.reminderMinutes) 分鐘"))
                    }
                }
            } header: {
                Text("休息提醒")
            } footer: {
                Text("連續閱讀達到設定時間後，閱讀頁會提醒你休息。中斷超過 5 分鐘會重新計算。")
            }
            Section {
                Picker("分組", selection: $grouping) {
                    ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if grouping == .works {
                    if stats.byWork.isEmpty { emptyRow }
                    ForEach(stats.byWork.prefix(Self.rankLimit), id: \.id) { entry in workRow(entry, top: top) }
                    if stats.byWork.count > Self.rankLimit {
                        let rest = Array(stats.byWork.dropFirst(Self.rankLimit))
                        DisclosureGroup {
                            ForEach(rest, id: \.id) { entry in workRow(entry, top: top) }
                        } label: {
                            othersLabel(count: rest.count, seconds: rest.reduce(0) { $0 + $1.seconds })
                        }
                    }
                } else {
                    if stats.byTag.isEmpty { emptyRow }
                    ForEach(stats.byTag.prefix(Self.rankLimit), id: \.tag) { entry in
                        row(title: entry.tag, subtitle: nil, seconds: entry.seconds, fraction: entry.seconds / top)
                    }
                    if stats.byTag.count > Self.rankLimit {
                        let rest = Array(stats.byTag.dropFirst(Self.rankLimit))
                        DisclosureGroup {
                            ForEach(rest, id: \.tag) { entry in
                                row(title: entry.tag, subtitle: nil, seconds: entry.seconds, fraction: entry.seconds / top)
                            }
                        } label: {
                            othersLabel(count: rest.count, seconds: rest.reduce(0) { $0 + $1.seconds })
                        }
                    }
                }
            } footer: {
                if grouping == .tags {
                    Text("同一部作品的時間會計入它的每一個 Fandom、配對、角色與其他標籤。")
                }
            }

        }
        .navigationTitle("閱讀時長")
    }

    /// 排行只直接顯示前幾名，其餘摺疊到「其他」
    private static let rankLimit = 10

    private func workRow(_ entry: (id: Int, seconds: Double), top: Double) -> some View {
        NavigationLink(value: WorkRoute(id: entry.id, title: app.readingTime.meta(for: entry.id)?.title ?? "")) {
            row(title: app.readingTime.meta(for: entry.id)?.title ?? "#\(entry.id)",
                subtitle: app.readingTime.meta(for: entry.id)?.authors.joined(separator: ", "),
                seconds: entry.seconds, fraction: entry.seconds / top)
        }
    }

    private func othersLabel(count: Int, seconds: Double) -> some View {
        HStack {
            Text("其他（\(count)）")
            Spacer(minLength: 8)
            Text(Self.format(seconds))
                .appFont(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var emptyRow: some View {
        Text("這段期間沒有閱讀紀錄").foregroundStyle(.secondary)
    }

    private func row(title: String, subtitle: String?, seconds: Double, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).lineLimit(2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(Self.format(seconds))
                    .appFont(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(.tint.opacity(0.6))
                    .frame(width: max(proxy.size.width * fraction, 4))
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }

    static func format(_ seconds: Double) -> String {
        if seconds > 0, seconds < 60 { return String(localized: "不到 1 分鐘") }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
