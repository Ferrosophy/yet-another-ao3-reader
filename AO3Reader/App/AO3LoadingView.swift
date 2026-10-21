import SwiftUI

/// 載入動畫：書本圖示原地循環淡入淡出（不使用 AO3 官方標誌，避免暗示官方授權）。`compact` 用於列表底部的分頁載入。
///
/// 透明度由 TimelineView 依時間計算，不使用 SwiftUI 動畫；並停用外層傳入的動畫，
/// 避免標誌出現時跟著版面變化從上方滑下來。
struct AO3LoadingView: View {
    var compact = false

    /// 一次淡入加淡出的時間（秒）
    private static let period = 1.8

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            let opacity = 0.15 + 0.85 * (0.5 - 0.5 * cos(phase * 2 * .pi))
            Image(systemName: "book.pages.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tint)
                .frame(width: compact ? 30 : 64)
                .opacity(opacity)
        }
        .padding(compact ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
        .transaction { $0.animation = nil }
        .accessibilityElement()
        .accessibilityLabel("載入中")
    }
}
