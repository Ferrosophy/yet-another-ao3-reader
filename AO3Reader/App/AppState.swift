import Foundation
import Observation

/// 全域依賴容器，透過 SwiftUI Environment 注入。應用沒有自己的帳號系統：
/// AO3 登入狀態來自 AO3 cookie，翻譯設定與 API Key 僅存在本機。
@MainActor
@Observable
final class AppState {
    let sources = SourceStore()
    let auth = AuthService()
    let translation: TranslationSettings
    let translator: TranslationService
    let appearance = AppearanceSettings()
    /// 作品卡片的簡介翻譯
    let summaries: SummaryTranslator

    init() {
        let translation = TranslationSettings()
        let translator = TranslationService()
        self.translation = translation
        self.translator = translator
        summaries = SummaryTranslator(settings: translation, translator: translator)
    }

    /// 目前來源的客戶端；切換來源時自動跟著變更。
    var client: AO3Client { AO3Client(baseURL: sources.selected.baseURL) }

    func selectSource(_ source: AO3Source) async {
        sources.selectedID = source.id
        await auth.refresh(client: client)
    }
}
