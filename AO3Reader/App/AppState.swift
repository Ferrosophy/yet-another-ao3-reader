import Foundation
import Observation

/// 全域依賴容器，透過 SwiftUI Environment 注入。應用沒有自己的帳號系統：
/// AO3 登入狀態來自 AO3 cookie，翻譯設定與 API Key 僅存在本機。
@MainActor
@Observable
final class AppState {
    let sources: SourceStore
    let auth = AuthService()
    let translation: TranslationSettings
    let translator: TranslationService
    let appearance: AppearanceSettings
    /// 作品卡片的簡介翻譯
    let summaries: SummaryTranslator
    /// 標籤翻譯（目標語言跟隨介面語言）
    let tags: TagTranslator
    /// 書架（本機資料）
    let bookshelf: BookshelfStore
    /// 時長管理
    let readingTime: ReadingTimeStore
    /// 個人資料同步（iCloud / WebDAV），與 AO3 帳號資料分開
    let sync: SyncService
    /// 本機使用者資料（資料來源為「本機保存」時使用）與它的同步
    let library: LocalLibraryStore
    let librarySync: LibrarySyncService
    /// 搜尋紀錄（與離線清單、閱讀時長一起同步）
    let searchHistory: SearchHistoryStore
    /// 書架的離線內容（原文、譯文與匯出檔）
    let offline: OfflineManager
    /// 新手引導：第一次開啟時顯示，也可從「設定 › 顯示教程」重新開啟
    var showsOnboarding = !UserDefaults.standard.bool(forKey: AppState.onboardingKey)
    static let onboardingKey = "onboarding.completed"

    init() {
        let sources = SourceStore()
        self.sources = sources
        let translation = TranslationSettings()
        let translator = TranslationService()
        self.translation = translation
        self.translator = translator
        summaries = SummaryTranslator(settings: translation, translator: translator)
        tags = TagTranslator(settings: translation, translator: translator)
        let appearance = AppearanceSettings()
        let bookshelf = BookshelfStore()
        let readingTime = ReadingTimeStore()
        self.appearance = appearance
        self.bookshelf = bookshelf
        self.readingTime = readingTime
        let searchHistory = SearchHistoryStore()
        self.searchHistory = searchHistory
        let sync = SyncService(bookshelf: bookshelf, readingTime: readingTime, appearance: appearance, translation: translation,
                               searchHistory: searchHistory)
        let library = LocalLibraryStore()
        self.sync = sync
        self.library = library
        librarySync = LibrarySyncService(library: library, shelfSync: sync)
        offline = OfflineManager(bookshelf: bookshelf, settings: translation, translator: translator) {
            AO3Client(baseURL: sources.selected.baseURL)
        }
    }

    /// 目前來源的客戶端；切換來源時自動跟著變更。
    var client: AO3Client { AO3Client(baseURL: sources.selected.baseURL) }

    func selectSource(_ source: AO3Source) async {
        sources.selectedID = source.id
        await auth.refresh(client: client)
    }
}
