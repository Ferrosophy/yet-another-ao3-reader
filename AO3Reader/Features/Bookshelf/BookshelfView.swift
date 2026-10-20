import PhotosUI
import SwiftUI

/// 離線：離線保存的作品（只顯示本機內容），可切換列表或網格（封面）顯示，支援多種排序與手動排序。
struct BookshelfView: View {
    @Environment(AppState.self) private var app
    @AppStorage("bookshelf.layout") private var layout: BookshelfLayout = .list
    @AppStorage("bookshelf.sort") private var sort: BookshelfSort = .recentlyRead
    @AppStorage("bookshelf.ascending") private var ascending = false
    @State private var coverTarget: Int?
    @State private var showsPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showsReorder = false
    @State private var errorMessage: String?
    @State private var shared: DownloadedFile?
    /// 卡片顯示時目前的卡片；進入作品再返回時保留位置
    @State private var currentIndex = 0

    private var items: [BookshelfItem] { app.bookshelf.sorted(by: sort, ascending: ascending) }

    var body: some View {
        Group {
            if app.bookshelf.items.isEmpty {
                ContentUnavailableView {
                    Label("沒有離線作品", systemImage: "arrow.down.circle")
                } description: {
                    Text("在閱讀頁點擊離線保存按鈕，或在作品列表中長按作品，即可離線保存。會先下載原文，再自動翻譯。")
                }
            } else if layout == .list {
                list
            } else {
                grid
            }
        }
        .navigationTitle("離線")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                NavigationLink {
                    DownloadsView()
                } label: {
                    Label("下載列表", systemImage: "arrow.down.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .sheet(isPresented: $showsReorder) { BookshelfReorderSheet() }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            guard let photoItem, let id = coverTarget else { return }
            Task {
                do {
                    if let data = try await photoItem.loadTransferable(type: Data.self) {
                        try app.bookshelf.setCover(data, for: id)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                self.photoItem = nil
                coverTarget = nil
            }
        }
        .sheet(item: $shared) { file in
            ActivityView(items: [file.url]).presentationDetents([.medium, .large])
        }
        .alert("無法套用封面", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("顯示方式", selection: $layout) {
                ForEach(BookshelfLayout.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            Picker("排序", selection: $sort) {
                ForEach(BookshelfSort.allCases) { Text($0.title).tag($0) }
            }
            if sort != .manual {
                Picker("順序", selection: $ascending) {
                    Text("遞減").tag(false)
                    Text("遞增").tag(true)
                }
            }
            Button("調整手動排序…", systemImage: "arrow.up.arrow.down") {
                sort = .manual
                showsReorder = true
            }
        } label: {
            Label("顯示與排序", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    /// 列表顯示：左右滑動的卡片（與瀏覽頁相同），卡片下方顯示離線狀態；只翻譯目前的卡片
    private var list: some View {
        let items = items
        return TabView(selection: $currentIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: WorkRoute(id: item.id, title: item.work.title)) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            WorkRow(work: item.work, translationActive: index == currentIndex, compact: false)
                            OfflineStatusView(id: item.id)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .glassEffect(.clear, in: .rect(cornerRadius: 24))
                    .contentShape(.rect(cornerRadius: 24))
                }
                .buttonStyle(.plain)
                .contextMenu { itemMenu(item) }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: items.count) {
            if currentIndex >= items.count { currentIndex = max(items.count - 1, 0) }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16)], spacing: 20) {
                ForEach(items) { item in
                    NavigationLink(value: WorkRoute(id: item.id, title: item.work.title)) {
                        VStack(alignment: .leading, spacing: 6) {
                            BookCoverView(work: item.work, image: app.bookshelf.covers[item.id])
                            Text(item.work.title)
                                .appFont(.footnote, weight: .medium)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let author = item.work.authors.first {
                                Text(author)
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            OfflineStatusView(id: item.id)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { itemMenu(item) }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: BookshelfItem) -> some View {
        Section("離線內容") {
            OfflineMenu(id: item.id, shared: $shared)
        }
        Button("更換封面", systemImage: "photo") {
            coverTarget = item.id
            showsPhotoPicker = true
        }
        if item.coverUpdatedAt != nil {
            Button("恢復預設封面", systemImage: "arrow.uturn.backward") { app.bookshelf.removeCover(for: item.id) }
        }
        Button("移除", systemImage: "trash", role: .destructive) { app.bookshelf.remove(item.id) }
    }
}

/// 作品封面：有自訂圖片時顯示圖片，否則依標題產生固定配色的預設封面。
struct BookCoverView: View {
    let work: WorkSummary
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                defaultCover
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var defaultCover: some View {
        let palette = Self.palettes[abs(work.id) % Self.palettes.count]
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [palette.0, palette.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 6) {
                Image("AO3Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 14)
                    .opacity(0.85)
                Spacer(minLength: 0)
                Text(work.title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                if let author = work.authors.first {
                    Text(author)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
        }
    }

    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.60, green: 0.00, blue: 0.00), Color(red: 0.32, green: 0.02, blue: 0.05)),
        (Color(red: 0.18, green: 0.29, blue: 0.48), Color(red: 0.08, green: 0.13, blue: 0.25)),
        (Color(red: 0.71, green: 0.52, blue: 0.20), Color(red: 0.42, green: 0.27, blue: 0.08)),
        (Color(red: 0.20, green: 0.42, blue: 0.33), Color(red: 0.08, green: 0.22, blue: 0.17)),
        (Color(red: 0.42, green: 0.27, blue: 0.53), Color(red: 0.20, green: 0.11, blue: 0.29)),
        (Color(red: 0.33, green: 0.33, blue: 0.36), Color(red: 0.13, green: 0.13, blue: 0.15)),
    ]
}

/// 手動排序：拖動調整書架順序（列表與網格共用）。
struct BookshelfReorderSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(app.bookshelf.sorted(by: .manual, ascending: true)) { item in
                    HStack(spacing: 12) {
                        BookCoverView(work: item.work, image: app.bookshelf.covers[item.id])
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.work.title).lineLimit(1)
                            if let author = item.work.authors.first {
                                Text(author).appFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onMove { app.bookshelf.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("手動排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
