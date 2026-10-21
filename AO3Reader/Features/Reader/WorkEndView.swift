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
        guard !isBusy else { return }
        if hasGivenKudos {
            alert = String(localized: "你已經給過這部作品 Kudos 了")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await client.leaveKudos(workID: workID)
            hasGivenKudos = true
            if !client.isDemo { KudosStore.add(client, workID) }
            alert = result == .given ? String(localized: "已送出 Kudos，謝謝你的支持！") : String(localized: "你已經給過這部作品 Kudos 了")
        } catch {
            alert = String(localized: "Kudos 送出失敗：\(error.localizedDescription)")
        }
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
            if !model.hasGivenKudos {
                Text("如果您喜歡這部作品，可以點一下 Kudos 送上小小的心意，或到原網站登入後留下評論。您的支持是作者最大的鼓勵。")
                    .font(font)
                    .foregroundStyle(color.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await model.leaveKudos() }
                } label: {
                    Group {
                        if model.isBusy {
                            ProgressView()
                        } else {
                            Text(verbatim: "❤️ Kudos")
                        }
                    }
                    .frame(minWidth: 96)
                }
                .buttonStyle(.glassProminent)
                Button(action: onComments) {
                    HStack(spacing: 6) {
                        Text(verbatim: "📖")
                        Text("評論")
                    }
                    .frame(minWidth: 96)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .alert("Kudos", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("好") {}
        } message: {
            Text(model.alert ?? "")
        }
    }
}
