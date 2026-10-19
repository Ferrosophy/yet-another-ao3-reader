import SwiftUI

/// 載入動畫：AO3 標誌循環淡入淡出。`compact` 用於列表底部的分頁載入。
struct AO3LoadingView: View {
    var compact = false

    var body: some View {
        Image("AO3Logo")
            .resizable()
            .scaledToFit()
            .frame(width: compact ? 34 : 76)
            .phaseAnimator([false, true]) { content, visible in
                content.opacity(visible ? 1 : 0.15)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .padding(compact ? 8 : 0)
            .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
            .accessibilityElement()
            .accessibilityLabel("載入中")
    }
}
