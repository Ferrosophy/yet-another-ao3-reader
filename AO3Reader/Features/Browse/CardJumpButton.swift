// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 卡片右下角的圓形序號按鈕：顯示目前是第幾部，點擊輸入序號快速跳到某部作品。
/// 序號超過目前已載入的數量時，透過 `loadUntil` 繼續載入下一頁。
struct CardJumpButton: View {
    @Binding var currentIndex: Int
    let count: Int
    /// 還有下一頁可載入
    var hasMore = false
    var loadUntil: ((Int) async -> Void)?

    @State private var showsInput = false
    @State private var input = ""
    @State private var isLoading = false

    var body: some View {
        Button {
            input = String(min(currentIndex + 1, count))
            showsInput = true
        } label: {
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(verbatim: "\(min(currentIndex + 1, count))")
                        .appFont(.caption, weight: .semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 4)
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(count == 0 || isLoading)
        .accessibilityLabel(Text("快速跳轉"))
        .accessibilityValue(Text(verbatim: "\(min(currentIndex + 1, count)) / \(count)\(hasMore ? "+" : "")"))
        .alert("跳到第幾部作品", isPresented: $showsInput) {
            TextField(text: $input, prompt: Text(verbatim: "1–\(count)")) { Text("作品序號") }
                .keyboardType(.numberPad)
            Button("跳轉") { jump() }
            Button("取消", role: .cancel) {}
        } message: {
            let hint = hasMore ? String(localized: "輸入序號跳到對應的作品；超過目前已載入的數量時會繼續載入。") : String(localized: "輸入序號跳到對應的作品。")
            Text(verbatim: "\(min(currentIndex + 1, count)) / \(count)\(hasMore ? "+" : "")\n\(hint)")
        }
    }

    private func jump() {
        guard let target = Int(input.filter(\.isNumber)), target >= 1 else { return }
        guard target > count, hasMore, let loadUntil else {
            currentIndex = min(target, count) - 1
            return
        }
        isLoading = true
        Task {
            await loadUntil(target)
            isLoading = false
            // 載入後仍不足時停在最後一部（卡片列表會再修正超出範圍的位置）
            currentIndex = target - 1
        }
    }
}
