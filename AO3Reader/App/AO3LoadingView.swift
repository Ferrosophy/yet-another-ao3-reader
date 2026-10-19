import SwiftUI

/// 載入動畫：AO3 標誌呼吸縮放。`compact` 用於列表底部的分頁載入。
struct AO3LoadingView: View {
    var compact = false

    var body: some View {
        Image("AO3Logo")
            .resizable()
            .scaledToFit()
            .frame(width: compact ? 34 : 76)
            .phaseAnimator([false, true]) { content, phase in
                content
                    .scaleEffect(phase ? 1.06 : 0.9)
                    .opacity(phase ? 1 : 0.5)
            } animation: { _ in
                .easeInOut(duration: 0.85)
            }
            .padding(compact ? 8 : 0)
            .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
            .accessibilityElement()
            .accessibilityLabel("載入中")
    }
}
