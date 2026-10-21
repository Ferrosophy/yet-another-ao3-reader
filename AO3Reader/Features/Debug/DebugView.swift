// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 除錯頁（設定 › 連續點擊版本號三次）：請求紀錄、偵測到的防護與驗證頁過程，可複製給開發者。
struct DebugView: View {
    @Environment(AppState.self) private var app
    @State private var problemsOnly = true
    /// 待複製的內容：複製前先提醒不要公開發布
    @State private var pendingCopy: String?

    private var entries: [DebugEntry] {
        DebugLog.shared.entries.filter { !problemsOnly || $0.isProblem || $0.kind == .verify }
    }

    var body: some View {
        List {
            Section {
                Toggle("展示模式", isOn: Binding(get: { app.sources.isDemo },
                                                set: { enabled in Task { await app.setDemoMode(enabled) } }))
            } header: {
                Text("展示")
            } footer: {
                Text("用於截取宣傳圖：來源切換為虛構的示範站，作品、作者與評論全部是 AI 生成的虛構內容，不會出現真實作者。重新開啟 App 或關閉此開關後回到官網。")
            }
            Section("環境") {
                LabeledContent("來源", value: app.sources.selected.baseURL.absoluteString)
                LabeledContent("Accept-Language", value: AO3Client.acceptLanguage)
                LabeledContent("Cookie", value: cookieNames)
                Text(verbatim: AO3Client.userAgent).appFont(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section {
                Toggle("只顯示問題與驗證", isOn: $problemsOnly)
                ForEach(entries) { entry in
                    NavigationLink {
                        DebugEntryDetail(entry: entry)
                    } label: {
                        row(entry)
                    }
                }
            } header: {
                Text("請求紀錄（\(entries.count)）")
            }
        }
        .navigationTitle("除錯")
        .toolbar {
            Menu {
                Button("複製全部紀錄", systemImage: "doc.on.doc") {
                    pendingCopy = environmentText + "\n\n" + DebugLog.shared.exportText()
                }
                Button("清除紀錄", systemImage: "trash", role: .destructive) { DebugLog.shared.clear() }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
        .modifier(CopyLogConfirmation(pending: $pendingCopy))
    }

    private func row(_ entry: DebugEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: entry.kind.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color(entry.kind).opacity(0.2), in: .capsule)
                    .foregroundStyle(color(entry.kind))
                if let status = entry.status { Text(verbatim: "\(status)").font(.caption.monospacedDigit()) }
                Spacer()
                Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Text(verbatim: entry.url).font(.caption).lineLimit(2)
            Text(verbatim: entry.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private func color(_ kind: DebugEntry.Kind) -> Color {
        switch kind {
        case .ok: .green
        case .verify: .blue
        case .cloudflare, .anubis: .orange
        case .http, .network, .parse: .red
        }
    }

    private var cookieNames: String {
        let names = HTTPCookieStorage.shared.cookies(for: app.sources.selected.baseURL)?.map(\.name).sorted() ?? []
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var environmentText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return [
            "YAFR \(version)",
            "Source: \(app.sources.selected.baseURL.absoluteString)",
            "User-Agent: \(AO3Client.userAgent)",
            "Accept-Language: \(AO3Client.acceptLanguage)",
            "Cookies: \(cookieNames)",
        ].joined(separator: "\n")
    }
}

/// 單筆紀錄的完整內容
private struct DebugEntryDetail: View {
    let entry: DebugEntry
    @State private var pendingCopy: String?

    var body: some View {
        ScrollView {
            Text(verbatim: entry.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(entry.kind.rawValue.uppercased())
        .toolbar {
            Button("複製", systemImage: "doc.on.doc") { pendingCopy = entry.text }
        }
        .modifier(CopyLogConfirmation(pending: $pendingCopy))
    }
}

/// 複製除錯紀錄前的提醒：已脫敏，但仍含瀏覽網址與頁面片段，不要公開發布
private struct CopyLogConfirmation: ViewModifier {
    @Binding var pending: String?
    @State private var copied = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("複製除錯紀錄？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible) {
                Button("複製") {
                    UIPasteboard.general.string = pending
                    pending = nil
                    copied = true
                }
            } message: {
                Text("紀錄已隱藏密碼、Cookie 與驗證權杖，但仍包含你瀏覽過的網址與部分頁面內容。請只私下提供給開發者，不要公開貼到 GitHub Issues。")
            }
            .alert("已複製", isPresented: $copied) { Button("好") {} }
    }
}
