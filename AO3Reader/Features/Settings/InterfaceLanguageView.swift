// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 介面語言選擇。iOS 會在 App 重新啟動後以所選語言載入全部介面文字。
struct InterfaceLanguageView: View {
    @State private var selected = InterfaceLanguage.selectedCode
    @State private var showsRestartNotice = false

    var body: some View {
        List {
            Section {
                row(code: nil, name: String(localized: "跟隨系統"))
            }
            Section {
                ForEach(InterfaceLanguage.all) { language in
                    row(code: language.code, name: language.name)
                }
            } footer: {
                Text("切換後請完全關閉並重新開啟 App，介面才會全部換成新語言。")
            }
        }
        .navigationTitle("介面語言")
        .alert("已切換介面語言", isPresented: $showsRestartNotice) {
            Button("好") {}
        } message: {
            Text("請從多工畫面關閉 App 後重新開啟。")
        }
    }

    private func row(code: String?, name: String) -> some View {
        Button {
            guard code != selected else { return }
            InterfaceLanguage.select(code)
            selected = code
            showsRestartNotice = true
        } label: {
            HStack {
                Text(verbatim: name).foregroundStyle(.primary)
                Spacer()
                if selected == code { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
