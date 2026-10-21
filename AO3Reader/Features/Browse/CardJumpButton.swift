// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 卡片列表下方的序號膠囊（例如「12 / 87+」）：點擊輸入序號快速跳到某部作品。
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
            HStack(spacing: 4) {
                if isLoading { ProgressView().controlSize(.mini) }
                Text(verbatim: "\(min(currentIndex + 1, count)) / \(count)\(hasMore ? "+" : "")")
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .appFont(.caption, weight: .medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(count == 0 || isLoading)
        .accessibilityLabel(Text("快速跳轉"))
        .alert("跳到第幾部作品", isPresented: $showsInput) {
            TextField(text: $input, prompt: Text(verbatim: "1–\(count)")) { Text("作品序號") }
                .keyboardType(.numberPad)
            Button("跳轉") { jump() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(hasMore ? "輸入序號跳到對應的作品；超過目前已載入的數量時會繼續載入。" : "輸入序號跳到對應的作品。")
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
