import SwiftUI

/// 來源管理：官網 + 使用者導入的鏡像站。鏡像必須與 AO3 官網 HTML 結構相同（例如 OTW 官方域名或反向代理）。
struct SourcesView: View {
    @Environment(AppState.self) private var app
    @State private var showsAdd = false

    var body: some View {
        List {
            Section {
                ForEach(app.sources.sources) { source in
                    Button {
                        Task { await app.selectSource(source) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).foregroundStyle(.primary)
                                Text(source.baseURL.absoluteString)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if source.id == app.sources.selectedID {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .deleteDisabled(source.isBuiltIn)
                }
                .onDelete { offsets in
                    for index in offsets { app.sources.remove(app.sources.sources[index]) }
                }
            } footer: {
                Text("所有搜尋、閱讀與登入都會經由所選來源進行。登入狀態依來源分開保存；請只使用你信任的鏡像，因為登入時密碼會傳送給該站點。")
            }
        }
        .navigationTitle("內容來源")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新增鏡像", systemImage: "plus") { showsAdd = true }
            }
        }
        .sheet(isPresented: $showsAdd) { AddSourceSheet() }
    }
}

private struct AddSourceSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlText = ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle, testing, ok(String?), failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱（可留空）", text: $name)
                    TextField("網址，例如 https://mirror.example.org", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("測試連線") { Task { await test() } }
                        .disabled(SourceStore.normalize(urlText) == nil || status == .testing)
                    switch status {
                    case .idle: EmptyView()
                    case .testing: ProgressView()
                    case .ok(let user):
                        Label(user.map { "可用，已登入為 \($0)" } ?? "可用的 AO3 來源", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新增鏡像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增") {
                        guard let url = SourceStore.normalize(urlText) else { return }
                        app.sources.add(name: name, url: url)
                        dismiss()
                    }
                    .disabled(SourceStore.normalize(urlText) == nil)
                }
            }
        }
    }

    private func test() async {
        guard let url = SourceStore.normalize(urlText) else { return }
        status = .testing
        do {
            let result = try await AO3Client(baseURL: url).probe()
            status = result.isAO3 ? .ok(result.username) : .failed(String(localized: "回應不像 AO3 頁面，可能不是相容的鏡像"))
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
