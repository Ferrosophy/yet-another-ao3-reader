<p align="center">
  <img src="docs/icon.png" width="128" alt="YAFR">
</p>

<h1 align="center">Yet another fanfic reader（YAFR）</h1>

<p align="center">
  原生 iOS 的 Archive of Our Own 閱讀器 · Liquid Glass · 沉浸式翻譯
</p>

<p align="center">
  <a href="https://github.com/Ferrosophy/yet-another-ao3-reader/releases/latest"><b>下載最新版</b></a> ·
  <a href="https://ferrosophy.github.io/yet-another-ao3-reader/">介紹網頁</a> ·
  <a href="https://github.com/Ferrosophy/yet-another-ao3-reader/issues">意見回饋</a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · 繁體中文 · <a href="README.en.md">English</a>
</p>

---

YAFR 是一個用 SwiftUI 打造的 [Archive of Our Own](https://archiveofourown.org)（AO3）第三方閱讀器，採用 iOS 26 的 Liquid Glass 設計。你可以瀏覽、搜尋、離線儲存作品，並以「原文在上、譯文在下」的方式閱讀任何語言的同人作品。

> 本 App 為非官方的第三方客戶端，與 AO3 及 Organization for Transformative Works（OTW）無關。

## 功能

### 閱讀與翻譯
- **沉浸式翻譯**：不取代原文，每段原文下方顯示譯文，也可切換為「僅譯文」。作品標題、標籤、簡介與作者注都能翻譯，可分別設定在瀏覽頁與閱讀頁顯示哪些。
- **多種翻譯服務**：
  - 免金鑰：Google、Bing、騰訊互動翻譯 TranSmart、火山、百度、有道、搜狗、DeepL 網頁版、Apple 翻譯（裝置上）。
  - 自備 API Key：Google Cloud、Microsoft Azure、DeepL API、OpenAI 相容服務（OpenAI / DeepSeek / OpenRouter / Groq / 自定義）、Anthropic Claude、Google Gemini。
- **閱讀模式**：滾動或翻頁（模擬、平滑、覆蓋、淡入淡出）；作者注依官網位置顯示在章首或章末。
- **外觀**：深色模式、主題色、自定義背景（純色或圖片）與文字顏色；字級、字重、行距、段距、字距、上下左右邊距；可匯入 TTF / OTF 字型，或從 Google Drive、百度網盤匯入。

### 瀏覽與搜尋
- **瀏覽**：最新作品，以及 Kudos、評論、點選排行榜，可依語言等條件篩選。
- **搜尋**：作品、標籤、使用者、合集四種範圍，附自動補全建議與搜尋記錄。
- **詳細搜尋與篩選**：與 AO3 的 Work Search 及 Sort and Filter 欄位一一對應，例如原作、分級、警告、分類、角色、配對、標籤包含 / 排除、字數、更新時間、點選、Kudos 等。

### 離線
- 加入「離線」的作品會自動**先下載原文、再翻譯**，沒有網路也能閱讀。原文與目標語言相同時只下載原文。
- 下載失敗會自動斷點續傳；可暫停、重試，或只更新新章節。
- 可分享為 App 產生的雙語 EPUB，或官網的 AZW3 / MOBI / PDF / HTML。作者設為「僅限登入使用者閱讀」的作品只能在 App 內離線閱讀，不提供匯出與分享。
- 後臺檢查新章節只讀取章節目錄頁，不會增加作品的點選數（Hits）。

### 帳號與資料
- **AO3 帳號**：登入後可使用收件箱、訂閱、閱讀記錄、稍後閱讀、書籤，並直接在 App 內加入書籤、訂閱作品 / 作者 / 系列。
- **本機儲存**：不登入也能把書籤、稍後閱讀、閱讀記錄、訂閱儲存在本機，也可從 AO3 匯入。
- **同步**：離線清單、閱讀進度、閱讀時長、偏好與搜尋記錄，可透過 iCloud 或 WebDAV（例如堅果雲）在裝置間同步。
- **時長管理**：閱讀時長統計，連續閱讀一段時間後提醒休息。

### 連線
- **映象源**：可自行加入與 AO3 結構相同的映象網址，切換後所有瀏覽、閱讀、登入都改走該來源。**App 不內建、不提供任何映象網址。**
- **新手引導**：第一次開啟時檢測能否連上 AO3，連不上時引導你加入映象源，並推薦可用的翻譯服務。
- **人機驗證**：遇到 Cloudflare 或 Anubis 驗證時自動彈出驗證頁，透過後自動回到 App。

### 多語言介面
繁體中文（臺灣、香港、澳門）、簡體中文、English、日本語、한국어、Français、Deutsch、Español、Português (Brasil)、Italiano、Nederlands、Русский、Українська、Polski、Türkçe、Tiếng Việt、ไทย、Bahasa Indonesia、हिन्दी、العربية。

## 安裝

需要 **iOS 26 或以上**的 iPhone。目前只透過本倉庫的 GitHub Releases 釋出，尚未上架 App Store 或 TestFlight。

1. 到 [Releases](https://github.com/Ferrosophy/yet-another-ao3-reader/releases/latest) 下載 `YAFR-<版本號>-unsigned.ipa`。
2. **核對校驗值**：Release 說明裡附有 SHA-256，也可下載同名的 `.sha256` 檔案。在電腦上執行 `shasum -a 256 YAFR-<版本號>-unsigned.ipa`（macOS / Linux）或 `Get-FileHash YAFR-<版本號>-unsigned.ipa`（Windows PowerShell），結果應與 Release 中的一致。
3. **簽名並安裝**：IPA 未簽名，需要用以下任一工具以你自己的 Apple ID 簽名後安裝：
   - [AltStore](https://altstore.io) 或 [SideStore](https://sidestore.io)：在 iPhone 上安裝後，用它開啟 IPA 即可；
   - [Sideloadly](https://sideloadly.io)：在電腦上連線 iPhone，拖入 IPA 並登入 Apple ID；
   - 自己的付費開發者證書。
4. 第一次開啟前，到 iPhone「設定 › 通用 › VPN 與裝置管理」信任你的開發者證書；iOS 16 以上還需要在「設定 › 隱私與安全性」開啟「開發者模式」。

**限制與風險**
- 使用免費 Apple ID 簽名時，App 每 **7 天**需要重新簽名一次（AltStore / SideStore 可在後臺自動續簽），而且同時最多隻能安裝 3 個自行簽名的 App。
- 簽名工具需要你的 Apple ID，請使用你信任的工具，建議另外開一個 Apple ID 專門用來簽名。
- **只從本倉庫的 Releases 下載 IPA。** 第三方「二次打包」或「免簽」版本可能被植入惡意程式碼，或竊取你的 AO3 帳號與 API Key；本專案不對非官方來源的安裝包負責。
- 升級時直接安裝新版 IPA 即可，本機資料會保留（使用同一個 Apple ID 簽名）。

### 在中國大陸使用
AO3 官網在中國大陸通常無法直接連線。第一次開啟時的新手引導會檢測連線，並教你加入映象源；之後也可以在「設定 › 內容來源」管理。Google 翻譯在中國大陸通常也無法使用，建議改用騰訊、火山或 Bing 翻譯。

> **使用映象登入有風險**：映象站不是 AO3 官方網站，映象的運營者能看到你輸入的帳號與密碼，以及登入後帳號裡的內容。App 的「測試連線」只檢查頁面格式是否相容，不代表映象安全可信。請儘量在官網登入，或只使用你信任的映象，並避免使用與其他網站相同的密碼。App 只接受 HTTPS 映象。

## 隱私

- App 本身沒有帳號系統，也沒有伺服器，不收集任何使用資料。
- AO3 的登入狀態以 Cookie 儲存在本機，不儲存你的密碼。
- 翻譯 API Key 只存在本機鑰匙圈，不會同步到 iCloud；翻譯時文字直接送往你選擇的翻譯服務。
- 同步資料只存放在你自己的 iCloud 或 WebDAV。

## 翻譯服務說明

- **資料會傳送給服務商**：開啟翻譯後，要翻譯的文字（正文、標題、標籤、簡介、作者注與評論）會傳送到你選擇的翻譯服務，並按該服務的隱私政策處理。**只有 Apple 翻譯在裝置上進行**，文字不會離開你的 iPhone。第一次在閱讀頁開啟雲端翻譯時，App 也會提示這一點。
- **非官方介面**：標示「免金鑰」或「網頁版」的服務（Google、Bing、騰訊 TranSmart、火山、百度、有道、搜狗、未填金鑰的 DeepL）使用的是網頁端的非官方介面，**未經服務商授權**，可能違反其服務條款、被限流或隨時失效。需要穩定、合規的使用時，請改用官方 API（Google Cloud Translation、Microsoft Azure、DeepL API、OpenAI 相容服務、Claude、Gemini 等，需自備 API Key）或 Apple 翻譯。
- **尊重作者意願**：作者在標籤、簡介或作者注中寫明「不要翻譯」「No AI」等時，App 預設不翻譯這部作品；閱讀時需要你確認才會翻譯，而且**不會使用 AI 翻譯服務**；離線儲存時也不會自動翻譯。
- **翻譯準確性**：機器翻譯可能有誤，不能取代原文。標籤、警告（Archive Warnings）與作者注尤其請以原文為準。

## 意見回饋與維護

- **Bug 與功能建議**：在 App 的「設定 › 意見回饋」可以直接開啟 [GitHub Issues](https://github.com/Ferrosophy/yet-another-ao3-reader/issues) 的問題回報表單，會自動帶上版本資訊；功能建議請選「功能建議」模板。
- **安全漏洞**：請勿公開，使用 Security 頁面的私密回報，詳見 [SECURITY.md](SECURITY.md)。
- **作者內容異議**：如果你是 AO3 作者，對作品在本 App 中的顯示、翻譯或離線儲存有疑慮，請使用「作者內容異議」模板。本 App 不託管、不轉載任何作品；作品可在 AO3 設定為僅限登入使用者閱讀，本 App 會遵守此限制。
- **除錯記錄**：如果某個映象源無法使用，在「設定」連點三下「應用版本」可以進入除錯頁。記錄已隱藏密碼、Cookie 與驗證令牌，但仍包含瀏覽過的網址，請私下提供，不要公開貼出。
- **維護預期**：這是個人業餘維護的專案，會盡量回復與修復，但無法保證響應時間或實現所有建議。AO3 改版時可能需要一段時間才能適配。

喜歡這個專案的話，可以在「設定 › 支援贊助」請開發者喝杯咖啡。

贊助只支援本 App 的開發者，與 AO3 及 OTW 無關，也不會解鎖任何功能，所有功能永久免費。如果想支援 AO3 本身，請前往 [OTW 官網](https://www.transformativeworks.org)捐款。

## 已知問題

- IPA 未簽名，需要自行簽名；使用免費 Apple ID 簽名時每 7 天需重新簽名一次。
- 只支援 iOS 26 或以上。
- 部分映象站的防護（Cloudflare 或 Anubis）可能讓 App 的請求在驗證後仍被拒絕，此時請換用其他映象。
- 免金鑰的翻譯服務屬於非官方介面，可能限流或暫時失效。
- 評論目前只能閱讀與翻譯，發表評論需到原網站。
- 部分新加入的介面文字，在中文與英文以外的語言中暫時以英文顯示。

## 備份與遷移

- **換新裝置**：在舊裝置開啟「設定 › 資料同步」（iCloud 或 WebDAV），新裝置選擇相同的同步方式後，即可取回離線清單、閱讀進度、閱讀時長、偏好設定、搜尋記錄與本機儲存的書籤等資料。
- **離線檔案**不會同步：新裝置會依離線清單自動重新下載。已匯出的 EPUB 等檔案可在「檔案」App 的 YAFR › Bookshelf 中另行備份。
- **不會同步的資料**：翻譯服務的 API Key、匯入的字型與背景圖片、翻譯快取與 AO3 登入狀態，換機後需要重新設定或登入。
- App 的本機資料也會包含在 iPhone 的 iCloud 備份或電腦備份中，從備份還原時一併恢復（翻譯快取除外）。

## 疑難排解

- **連不上 AO3**：在「設定 › 內容來源」加入你信任的映象源；遇到人機驗證時照畫面完成即可。
- **AO3 暫時限制訪問（HTTP 429）**：App 會停止重試並顯示需要等待的時間，請稍後再試。
- **頁面讀取失敗或內容不完整**：可能是 AO3 改版。請在「設定」連點三下「應用版本」開啟除錯頁，複製記錄後到 Issues 回報，我們會更新解析規則。已離線儲存的作品不受影響。
- **翻譯失敗**：到「設定 › 翻譯服務」換用其他服務（例如裝置上的 Apple 翻譯）；不翻譯時原文閱讀不受影響。
- **離線閱讀**不需要網路；書架上已下載的作品隨時可讀。

## 隱私與安全

- [隱私政策](PRIVACY.md)：資料流向與刪除方式。
- [安全政策](SECURITY.md)：請透過 GitHub 的私密回報功能回報安全漏洞，不要公開發布。
- [更新日誌](CHANGELOG.md)

## 授權條款

本專案以 [GNU 通用公共授權條款](LICENSE)第 3 版或（由你選擇的）任何更新的版本開源（SPDX：`GPL-3.0-or-later`），每個原始碼檔案開頭都有相同的宣告。你可以自由使用、修改和再發布，但再發布（包括修改後的版本）時必須以相同的授權條款公開原始碼。第三方依賴 [SwiftSoup](https://github.com/scinfu/SwiftSoup) 採用 MIT 授權條款。

## 開發

### 版本與更新

- 版本號遵循[語義化版本](https://semver.org/lang/zh-TW/)：`主版本.次版本.修訂號`。不相容的變更增加主版本，新功能增加次版本，修復與小改動增加修訂號。
- 每個版本的變更記錄在 [CHANGELOG.md](CHANGELOG.md)，已知問題列在上方「已知問題」。
- 正式版釋出在 GitHub Releases，並附上 IPA 的 SHA-256 校驗值。

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
├── Core/           網路（AO3Client、來源、除錯記錄）、解析（AO3Parser）、登入、離線、儲存與同步
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

IPA 檔名為 `YAFR-<版本號>-unsigned.ipa`。

## 注意事項

- 請遵守 AO3 的[服務條款](https://archiveofourown.org/tos)。App 只在你操作時載入頁面，遇到 HTTP 429 會停止重試並顯示等待時間。
- 免金鑰的翻譯服務屬於非官方介面，可能限流或變更；需要穩定時建議使用自備 API Key 的服務。
- 作品的著作權屬於原作者。請勿把離線或匯出的作品與譯文再散佈。
