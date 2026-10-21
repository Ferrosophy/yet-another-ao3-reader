# Yet another AO3 reader（YAAO3R）

iOS 原生 · Liquid Glass · 沉浸式翻譯

一個原生 SwiftUI 的 Archive of Our Own 閱讀器草案，採用 iOS 26 的 **Liquid Glass** 設計語言。

> 狀態：**草案 / 骨架**。架構與主要流程皆已實作，尚未在真機上完整驗證，詳見文末「待辦」。

## 功能

| 功能 | 說明 |
| --- | --- |
| AO3 帳號登入 | 原生表單（取 `authenticity_token` → `POST /users/login`），失敗或遇 Cloudflare 驗證時可改用 WKWebView 網頁登入並同步 Cookie。不保存密碼。 |
| 官網原生搜尋與篩選 | `FilterSheet` 與 AO3「Work Search」欄位一一對應（關鍵字、標題、作者、更新時間、完結、Crossover、字數、語言、Fandom、分級、Warnings、分類、角色、配對、其他標籤、點擊/Kudos/評論/書籤、排序），原樣產生 `work_search[...]` 參數交給 AO3 伺服器處理。 |
| 鏡像來源 | 可新增鏡像（含連線測試），切換後所有搜尋、閱讀、登入都走該來源。 |
| 新手引導 | 第一次開啟時檢測能否連上來源，連不上時引導加入鏡像源並推薦可用的翻譯服務；可在「設定 › 顯示教程」重看。 |
| 個人列表 | 登入後可瀏覽收件匣（收到的評論）、訂閱（作品 / 系列 / 用戶）、閱讀紀錄、稍後閱讀、書籤。 |
| 標籤 / 用戶 / 合集 | 搜尋分頁支援作品、標籤（Tag Search）、用戶（People Search）、合集（Collections）四種範圍；點標籤可查看該標籤下所有作品，並用「Sort and Filter」再包含 / 排除標籤篩選。篩選表單的標籤欄位會向 AO3 自動完成查找匹配標籤。 |
| 帳號操作 | 閱讀頁右上角可加入 / 編輯 / 移除書籤、稍後閱讀、訂閱作品 / 作者 / 系列，直接提交官網表單，同步到 AO3 帳號。 |
| 書架 | 本機收藏作品，列表（作品卡片）或網格（封面，可自訂）顯示；最近閱讀、加入時間、標題、作者或手動排序。可設為打開 App 的第一頁。 |
| 時長管理 | 閱讀時長統計（今天 / 7 天 / 30 天 / 全部，依作品或標籤），連續閱讀達設定時間時提醒休息。 |
| 離線 | 離線保存即自動先下載原文、再翻譯，離線閱讀；匯出為 App 產生的雙語 EPUB 或官網 AZW3 / MOBI / PDF / HTML（「檔案」App 可見）。顯示進度與大小，可暫停、重試、只更新新章節。 |
| 資料同步 | 使用者資料可選 AO3 帳號（直接讀寫 AO3）或本機保存（可從 AO3 匯入）；書架（含進度、時長、偏好）與本機資料各自選擇 iCloud 或 WebDAV 同步（推薦堅果雲，設定頁內附教學）。 |
| Cloudflare | 官網或鏡像要求人機驗證（Cloudflare / Anubis）時自動彈出驗證頁，通過後 Cookie 同步回 App，並以 App 實際請求確認已通過。 |
| 瀏覽 | 最新作品，以及 Kudos / 評論 / 點擊排行榜（24 小時、本週、本月、今年、全部）；語言清單從 AO3 搜尋表單讀取。 |
| 閱讀模式 | 捲動或翻頁（仿真、平滑、覆蓋、淡入淡出）；標題列與控制列可選浮動（自動隱藏）或鎖定。 |
| 外觀 | 深色模式；主題色（書房紅 #990000 預設、燈塔金、海軍藍）；淺色 / 深色模式各自的背景（純色或圖片，可選加亮 / 加暗淡化）與文字顏色；字級、字重、行距、段距、字距、左右 / 上下邊距；蘋果內建字體或匯入 TTF / OTF；自訂譯文樣式、字級、顏色、斜體。 |
| 沉浸式翻譯 | **不取代原文**：每段原文下方顯示譯文（強調色側條），也可切換為「僅譯文」。只翻譯螢幕上可見的段落並預取後續幾段，合併批次送出並快取。 |
| 翻譯服務 | Google 翻譯（免金鑰）、Bing 翻譯（免金鑰）、Microsoft Translator（Azure）、Google Cloud Translation、OpenAI 相容 API（OpenAI / DeepSeek / OpenRouter / Groq / 自訂 Base URL）、Anthropic Claude、Google Gemini。 |
| 多語言 | 繁中、繁中（香港）、簡中、英、日、韓、法、德、西、葡、義、俄、烏、波、土、越、泰、印尼、阿拉伯文，閱讀中可隨時切換。 |
| 無帳號系統 | 應用本身沒有帳號與伺服器。API Key 只存在本機鑰匙圈（`WhenUnlockedThisDeviceOnly`、不同步 iCloud），翻譯時直接送往服務商。 |

## Liquid Glass 設計

- **Tab Bar**：系統玻璃浮動分頁列（書架 / 瀏覽 / 帳號 / 設定 / 搜尋），搜尋分頁使用 `Tab(role: .search)`，捲動時 `.tabBarMinimizeBehavior(.onScrollDown)` 自動縮小。
- **閱讀器控制列**：`GlassEffectContainer` 內的圓形與膠囊玻璃按鈕（上一章、章節/字體、翻譯、語言、下一章）。開啟翻譯時翻譯按鈕染上強調色，語言膠囊以 `glassEffectID` 從翻譯按鈕形變流出；往下閱讀時控制列隱藏，上滑或輕點時出現。
- **按鈕**：主要操作 `.buttonStyle(.glassProminent)`，次要操作 `.buttonStyle(.glass)`。
- **內容層**：閱讀頁頂部 `.scrollEdgeEffectStyle(.soft)`；作品摘要、登入表單、分級徽章使用 `.glassEffect(in:)`。
- 原則：玻璃只用於「浮在內容上的控制層」，正文保持純粹排版，確保長時間閱讀的可讀性。

## 架構

```
AO3Reader/
├── App/                 AO3ReaderApp、RootView（TabView）、AppState（依賴容器）
├── Models/              WorkSummary / WorkDetail / Chapter / Paragraph、WorkSearchQuery
├── Core/
│   ├── Networking/      AO3Client（共用 Cookie 的 URLSession）、SourceStore（官網 + 鏡像）
│   ├── Parsing/         AO3Parser（SwiftSoup，選擇器集中管理）
│   ├── Auth/            AuthService（登入/登出/狀態偵測）
│   └── Storage/         KeychainStore（API Key）
├── Translation/
│   ├── TranslationProvider.swift   協定：[段落] → [譯文]，一一對應
│   ├── Providers/                   Google（網頁/Cloud）、LLMTranslator + OpenAI/Claude/Gemini 後端
│   ├── TranslationService.swift     actor，SHA256 快取（記憶體 + Caches 目錄）
│   └── TranslationSettings.swift    設定（UserDefaults）+ Key（Keychain）+ Provider 工廠
└── Features/
    ├── Browse/          最新、搜尋、進階篩選、分頁列表
    ├── Reader/          ReaderView（玻璃控制列）、ReaderViewModel（翻譯排程）、雙語段落
    ├── Account/         原生登入、網頁登入、個人列表
    └── Settings/        來源管理、翻譯設定、隱私
```

### 沉浸式翻譯流程

1. 段落 `onAppear` → 標記 `.loading` 並加入佇列，同時預取後面 4 段。
2. 250ms 防抖後，依服務的 `maxBatchCharacters` 取出一批段落。
3. `TranslationService` 先查快取（鍵 = 服務/模型 + 目標語言 + 原文），只送出未命中的段落。
4. AI 服務收到 JSON 字串陣列、回傳等長 JSON 陣列；若段數不符則二分重試直到逐段翻譯，保證段落對齊。
5. 譯文依段落 ID 寫回，顯示在原文下方。切換語言/服務時遞增 `generation` 丟棄過期結果。

### 鏡像來源

鏡像需與 AO3 官網 HTML 結構相同（解析器共用）。Cookie 依網域隔離，因此每個來源需各自登入。登入時密碼會送往所選來源，請只使用信任的鏡像。

## 建置

需求：Xcode 26+、iOS 26 SDK。

```bash
brew install xcodegen
xcodegen generate
open AO3Reader.xcodeproj
```

相依套件：[SwiftSoup](https://github.com/scinfu/SwiftSoup)（SPM，HTML 解析）。

### 雲端建置 IPA（GitHub Actions）

不需要本機 Mac：`.github/workflows/build-ipa.yml` 在 GitHub 的 macOS runner 上編譯並打包**未簽名** IPA，簽名請自行處理。

| 觸發方式 | 版本號（CFBundleShortVersionString） | 產物 |
| --- | --- | --- |
| 推送 tag `v0.1.0` | 取自 tag：`0.1.0` | Artifact + GitHub Release（附 IPA） |
| Actions 頁面手動執行 | 輸入的版本號 | Artifact |
| PR / 推送 main | `project.yml` 的 `MARKETING_VERSION` | Artifact |

建置號（CFBundleVersion）一律為 Actions 的 `run_number`。IPA 檔名：`YAAO3R-<版本號>-unsigned.ipa`，版本號最後一位代表第幾次修改（每次編譯遞增）。

發佈新版本：

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## 注意事項

- 請遵守 AO3 [服務條款](https://archiveofourown.org/tos)，避免高頻請求；遇到 429 時客戶端會顯示 `Retry-After`。
- Google 翻譯免金鑰端點屬非官方介面，可能限流或變更；正式使用建議 Google Cloud 或 AI 服務。
- 譯文與快取僅存於本機 Caches 目錄，可在設定中清除。

## 待辦

- [ ] 在真機上驗證登入流程與 Cloudflare 情境
- [ ] 標籤頁瀏覽（`/tags/{tag}/works`）與「包含/排除標籤」篩選
- [ ] Kudos、書籤、訂閱、評論等需登入的寫入操作
- [x] 離線下載整部作品（含譯文）
- [ ] 作品語境（Fandom、角色）自動加入 AI 提示詞，提升人名一致性
- [ ] 閱讀進度精確到段落、iPad 雙欄排版
