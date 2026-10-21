<p align="center">
  <img src="docs/icon.png" width="128" alt="YAAO3R">
</p>

<h1 align="center">Yet another AO3 reader（YAAO3R）</h1>

<p align="center">
  原生 iOS 的 Archive of Our Own 閱讀器 · Liquid Glass · 沉浸式翻譯
</p>

<p align="center">
  <a href="https://github.com/Ferrosophy/yet-another-ao3-reader/releases/latest"><b>下載最新版</b></a> ·
  <a href="https://ferrosophy.github.io/yet-another-ao3-reader/">介紹網頁</a> ·
  <a href="https://github.com/Ferrosophy/yet-another-ao3-reader/issues">意見回饋</a>
</p>

<p align="center">
  繁體中文 · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.en.md">English</a>
</p>

---

YAAO3R 是一個用 SwiftUI 打造的 [Archive of Our Own](https://archiveofourown.org)（AO3）第三方閱讀器，採用 iOS 26 的 Liquid Glass 設計。你可以瀏覽、搜尋、離線保存作品，並以「原文在上、譯文在下」的方式閱讀任何語言的同人作品。

> 本 App 為非官方的第三方客戶端，與 AO3 及 Organization for Transformative Works（OTW）無關。

## 功能

### 閱讀與翻譯
- **沉浸式翻譯**：不取代原文，每段原文下方顯示譯文，也可切換為「僅譯文」。作品標題、標籤、簡介與作者註都能翻譯，可分別設定在瀏覽頁與閱讀頁顯示哪些。
- **多種翻譯服務**：
  - 免金鑰：Google、Bing、騰訊交互翻譯 TranSmart、火山、百度、有道、搜狗、DeepL 網頁版、Apple 翻譯（裝置上）。
  - 自備 API Key：Google Cloud、Microsoft Azure、DeepL API、OpenAI 相容服務（OpenAI / DeepSeek / OpenRouter / Groq / 自訂）、Anthropic Claude、Google Gemini。
- **閱讀模式**：捲動或翻頁（仿真、平滑、覆蓋、淡入淡出）；作者註依官網位置顯示在章首或章末。
- **外觀**：深色模式、主題色、自訂背景（純色或圖片）與文字顏色；字級、字重、行距、段距、字距、上下左右邊距；可匯入 TTF / OTF 字體，或從 Google Drive、百度網盤匯入。

### 瀏覽與搜尋
- **瀏覽**：最新作品，以及 Kudos、評論、點擊排行榜，可依語言等條件篩選。
- **搜尋**：作品、標籤、用戶、合集四種範圍，附自動完成建議與搜尋紀錄。
- **詳細搜尋與篩選**：與 AO3 的 Work Search 及 Sort and Filter 欄位一一對應，例如原作、分級、警告、分類、角色、配對、標籤包含 / 排除、字數、更新時間、點擊、Kudos 等。

### 離線
- 加入「離線」的作品會自動**先下載原文、再翻譯**，沒有網路也能閱讀。原文與目標語言相同時只下載原文。
- 下載失敗會自動斷點續傳；可暫停、重試，或只更新新章節。
- 可分享為 App 產生的雙語 EPUB，或官網的 AZW3 / MOBI / PDF / HTML。

### 帳號與資料
- **AO3 帳號**：登入後可使用收件匣、訂閱、閱讀紀錄、稍後閱讀、書籤，並直接在 App 內加入書籤、訂閱作品 / 作者 / 系列。
- **本機保存**：不登入也能把書籤、稍後閱讀、閱讀紀錄、訂閱保存在本機，也可從 AO3 匯入。
- **同步**：離線清單、閱讀進度、閱讀時長、偏好與搜尋紀錄，可透過 iCloud 或 WebDAV（例如堅果雲）在裝置間同步。
- **時長管理**：閱讀時長統計，連續閱讀一段時間後提醒休息。

### 連線
- **鏡像源**：可自行加入與 AO3 結構相同的鏡像網址，切換後所有瀏覽、閱讀、登入都改走該來源。**App 不內建、不提供任何鏡像網址。**
- **新手引導**：第一次開啟時檢測能否連上 AO3，連不上時引導你加入鏡像源，並推薦可用的翻譯服務。
- **人機驗證**：遇到 Cloudflare 或 Anubis 驗證時自動彈出驗證頁，通過後自動回到 App。

### 多語言介面
繁體中文（台灣、香港、澳門）、简体中文、English、日本語、한국어、Français、Deutsch、Español、Português (Brasil)、Italiano、Nederlands、Русский、Українська、Polski、Türkçe、Tiếng Việt、ไทย、Bahasa Indonesia、हिन्दी、العربية。

## 安裝

- 需要 **iOS 26 或以上**的 iPhone。
- 到 [Releases](https://github.com/Ferrosophy/yet-another-ao3-reader/releases/latest) 下載 `YAAO3R-<版本號>-unsigned.ipa`。
- IPA **未簽名**，請用 [AltStore](https://altstore.io)、[SideStore](https://sidestore.io)、[Sideloadly](https://sideloadly.io) 或自己的開發者憑證簽名後安裝。
- 使用免費 Apple ID 簽名時，App 每 7 天需要重新簽名一次。

### 在中國大陸使用
AO3 官網在中國大陸通常無法直接連線。第一次開啟時的新手引導會檢測連線，並教你加入鏡像源；之後也可以在「設定 › 內容來源」管理。Google 翻譯在中國大陸通常也無法使用，建議改用騰訊、火山或 Bing 翻譯。

> 登入時密碼會傳送給所選的來源，請只使用你信任的鏡像。

## 隱私

- App 本身沒有帳號系統，也沒有伺服器，不收集任何使用資料。
- AO3 的登入狀態以 Cookie 保存在本機，不保存你的密碼。
- 翻譯 API Key 只存在本機鑰匙圈，不會同步到 iCloud；翻譯時文字直接送往你選擇的翻譯服務。
- 同步資料只存放在你自己的 iCloud 或 WebDAV。

## 意見回饋

在 App 的「設定 › 意見回饋」可以直接開啟 [GitHub Issues](https://github.com/Ferrosophy/yet-another-ao3-reader/issues)，系統會自動附上版本資訊。如果某個鏡像源無法使用，在「設定」連點三下「應用版本」可以進入除錯頁，複製紀錄後一起附上。

喜歡這個專案的話，可以在「設定 › 支持贊助」請開發者喝杯咖啡。

贊助只支持本 App 的開發者，與 AO3 及 OTW 無關，也不會解鎖任何功能，所有功能永久免費。如果想支持 AO3 本身，請前往 [OTW 官網](https://www.transformativeworks.org)捐款。

## 已知問題

- IPA 未簽名，需要自行簽名；使用免費 Apple ID 簽名時每 7 天需重新簽名一次。
- 只支援 iOS 26 或以上。
- 部分鏡像站的防護（Cloudflare 或 Anubis）可能讓 App 的請求在驗證後仍被拒絕，此時請換用其他鏡像。
- 免金鑰的翻譯服務屬於非官方介面，可能限流或暫時失效。
- 評論目前只能閱讀與翻譯，發表評論需到原網站。
- 翻頁模式下，文末的 Kudos 與評論面板需在最後一頁繼續往後翻才會出現。
- 部分新加入的介面文字，在中文與英文以外的語言中暫時以英文顯示。

## 備份與遷移

- **換新裝置**：在舊裝置開啟「設定 › 資料同步」（iCloud 或 WebDAV），新裝置選擇相同的同步方式後，即可取回離線清單、閱讀進度、閱讀時長、偏好設定、搜尋紀錄與本機保存的書籤等資料。
- **離線檔案**不會同步：新裝置會依離線清單自動重新下載。已匯出的 EPUB 等檔案可在「檔案」App 的 YAAO3R › Bookshelf 中另行備份。
- **不會同步的資料**：翻譯服務的 API Key、匯入的字體與背景圖片、翻譯快取與 AO3 登入狀態，換機後需要重新設定或登入。
- App 的本機資料也會包含在 iPhone 的 iCloud 備份或電腦備份中，從備份還原時一併恢復（翻譯快取除外）。

## 疑難排解

- **連不上 AO3**：在「設定 › 內容來源」加入你信任的鏡像源；遇到人機驗證時照畫面完成即可。
- **AO3 暫時限制存取（HTTP 429）**：App 會停止重試並顯示需要等待的時間，請稍後再試。
- **頁面讀取失敗或內容不完整**：可能是 AO3 改版。請在「設定」連點三下「應用版本」打開除錯頁，複製紀錄後到 Issues 回報，我們會更新解析規則。已離線保存的作品不受影響。
- **翻譯失敗**：到「設定 › 翻譯服務」換用其他服務（例如裝置上的 Apple 翻譯）；不翻譯時原文閱讀不受影響。
- **離線閱讀**不需要網路；書架上已下載的作品隨時可讀。

## 隱私與安全

- [隱私政策](PRIVACY.md)：資料流向與刪除方式。
- [安全政策](SECURITY.md)：請透過 GitHub 的私密回報功能回報安全漏洞，不要公開發布。
- [更新日誌](CHANGELOG.md)

## 開發

需要 Xcode 26 以上與 iOS 26 SDK。

```bash
brew install xcodegen
xcodegen generate
open AO3Reader.xcodeproj
```

- 相依套件：[SwiftSoup](https://github.com/scinfu/SwiftSoup)（Swift Package Manager，用於解析 HTML）。
- 架構與需求規格見 [SPEC.md](SPEC.md)；介面多語系的產生流程見 [scripts/l10n](scripts/l10n/README.md)。

```
AO3Reader/
├── App/            進入點、分頁、全域狀態
├── Models/         作品、章節、段落、搜尋條件
├── Core/           網路（AO3Client、來源、除錯紀錄）、解析（AO3Parser）、登入、離線、儲存與同步
├── Translation/    翻譯服務、快取、設定
└── Features/       瀏覽、搜尋、閱讀、離線、帳號、設定、新手引導
```

### 雲端建置

`.github/workflows/build-ipa.yml` 會在 GitHub Actions 的 macOS runner 上產生**未簽名** IPA：

| 觸發方式 | 版本號 | 產物 |
| --- | --- | --- |
| 推送 main / PR | `project.yml` 的 `MARKETING_VERSION` | Artifact |
| 手動執行（可填版本號） | 輸入的版本號 | Artifact；勾選「發行」時另建 GitHub Release |
| 推送 tag `v1.2.3` | `1.2.3` | Artifact + GitHub Release |

IPA 檔名為 `YAAO3R-<版本號>-unsigned.ipa`。

## 注意事項

- 請遵守 AO3 的[服務條款](https://archiveofourown.org/tos)。App 只在你操作時載入頁面，遇到 HTTP 429 會停止重試並顯示等待時間。
- 免金鑰的翻譯服務屬於非官方介面，可能限流或變更；需要穩定時建議使用自備 API Key 的服務。
- 作品的著作權屬於原作者。請勿把離線或匯出的作品與譯文再散布。
