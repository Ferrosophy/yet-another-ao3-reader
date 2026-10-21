// SPDX-License-Identifier: GPL-3.0-or-later
import Observation
import SwiftUI

/// 本機記錄已給過 Kudos 的作品（依來源網域），避免重複送出
enum KudosStore {
    private static let storageKey = "kudos.given"

    private static func key(_ client: AO3Client, _ workID: Int) -> String { "\(client.baseURL.host() ?? "")#\(workID)" }

    static func contains(_ client: AO3Client, _ workID: Int) -> Bool {
        (UserDefaults.standard.stringArray(forKey: storageKey) ?? []).contains(key(client, workID))
    }

    static func add(_ client: AO3Client, _ workID: Int) {
        var list = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        let entry = key(client, workID)
        guard !list.contains(entry) else { return }
        list.append(entry)
        UserDefaults.standard.set(list, forKey: storageKey)
    }
}

/// 文末的 Kudos 狀態
@MainActor
@Observable
final class WorkEndModel {
    let workID: Int
    let client: AO3Client
    private(set) var isBusy = false
    private(set) var hasGivenKudos: Bool
    var alert: String?

    init(workID: Int, client: AO3Client) {
        self.workID = workID
        self.client = client
        hasGivenKudos = !client.isDemo && KudosStore.contains(client, workID)
    }

    func leaveKudos() async {
        // 已給過時每次點擊都提示（先清除再設定，讓同樣的提示能再次彈出）
        if hasGivenKudos {
            show(String(localized: "你已經給過這部作品 Kudos 了"))
            return
        }
        guard !isBusy else {
            show(String(localized: "正在送出 Kudos，請稍候"))
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await client.leaveKudos(workID: workID)
            hasGivenKudos = true
            if !client.isDemo { KudosStore.add(client, workID) }
            show(result == .given ? String(localized: "已送出 Kudos，謝謝你的支持！") : String(localized: "你已經給過這部作品 Kudos 了"))
        } catch {
            show(String(localized: "Kudos 送出失敗：\(error.localizedDescription)"))
        }
    }

    private func show(_ message: String) {
        alert = nil
        Task { @MainActor in alert = message }
    }
}

/// 文末：支持作者的提示、Kudos 按鈕與評論入口（捲動模式顯示在最後一章結尾，翻頁模式在最後一頁繼續翻頁時彈出）
struct WorkEndView: View {
    let model: WorkEndModel
    var font: Font = .body
    var color: Color = .primary
    var onComments: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("如果您喜歡這部作品，可以點一下 Kudos 送上小小的心意，或到原網站登入後留下評論。您的支持是作者最大的鼓勵。")
                .font(font)
                .foregroundStyle(color.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    Task { await model.leaveKudos() }
                } label: {
                    // 文字一直保留，送出中只暫時隱藏並疊上進度圈（替換整個內容會讓玻璃按鈕的文字消失）
                    Label {
                        Text(verbatim: "Kudos")
                    } icon: {
                        Image(systemName: "heart.fill")
                    }
                    .opacity(model.isBusy ? 0 : 1)
                    .overlay {
                        if model.isBusy { ProgressView().tint(.white) }
                    }
                    .frame(minWidth: 96)
                }
                .buttonStyle(.glassProminent)
                Button(action: onComments) {
                    Label("評論", systemImage: "text.bubble.fill")
                        .frame(minWidth: 96)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        // 提示由閱讀頁統一彈出（翻頁模式的章末頁在翻頁器內，從那裡彈出可能失敗）
    }
}
