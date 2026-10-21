# 隱私政策 / Privacy Policy

最後更新：2026-10-21 · 適用於 YAAO3R（Yet another AO3 reader）1.0 及以上版本

YAAO3R 是獨立開發的非官方 AO3 閱讀器，與 Archive of Our Own（AO3）及 Organization for Transformative Works（OTW）沒有官方關聯。

## 我們不收集任何資料

- App **沒有開發者伺服器**、沒有帳號系統，也**沒有任何分析、追蹤或廣告 SDK**。
- 開發者收不到你的閱讀內容、搜尋紀錄、帳號或任何使用資料。

## 資料會傳到哪裡

| 資料 | 傳送對象 | 說明 |
| --- | --- | --- |
| 瀏覽、搜尋、閱讀的請求 | 你選擇的內容來源（AO3 官網或你自行加入的鏡像） | 與用瀏覽器瀏覽該網站相同。 |
| AO3 帳號與密碼 | 只在登入時送往你選擇的內容來源 | **密碼不會保存**，也不會寫入除錯紀錄。登入後只在本機保存該網站的 Cookie。使用鏡像登入時密碼會送往鏡像站，請只使用你信任的鏡像。 |
| 要翻譯的文字 | 你選擇的翻譯服務（Google、Bing、騰訊、火山、DeepL、OpenAI 相容服務、Claude、Gemini 等） | 只送出需要翻譯的段落、標題、簡介或評論。各服務如何處理資料請參考其隱私政策。Apple 翻譯在裝置上進行。 |
| 翻譯服務的 API Key | 只送往對應的翻譯服務 | 保存在裝置鑰匙圈（僅此裝置、不同步 iCloud）。 |
| 同步資料（離線清單、閱讀進度、閱讀時長、偏好、搜尋紀錄、本機書籤等） | 你自己的 iCloud 或 WebDAV（例如堅果雲） | 預設不開啟。WebDAV 密碼保存在鑰匙圈。不包含 API Key。 |

## 保存在裝置上的資料

設定、離線作品與匯出檔（「檔案」App 的 YAAO3R › Bookshelf）、書架、閱讀紀錄與進度、翻譯快取、匯入的字體與背景圖、登入 Cookie、除錯紀錄。

除錯紀錄（設定 › 連點版本號三次）只保存在本機，記錄請求網址、狀態與部分回應內容；驗證權杖與 Cookie 的值會被隱藏。只有你主動複製時才會離開裝置。

## 刪除資料

- **App 內**：設定 › 隱私 ›「清除所有本地資料」會刪除上述所有本機資料、鑰匙圈中的 API Key 與密碼、Cookie 與網頁資料，完成後 App 會關閉。
- **只清除翻譯快取**：設定 › 隱私 ›「清除翻譯快取」。
- **解除安裝**：刪除 App 即刪除所有本機資料（鑰匙圈項目可能由系統保留，建議先使用「清除所有本地資料」）。
- **同步資料**：存放在你自己的 iCloud 或 WebDAV。iCloud 資料可在 iPhone「設定 › Apple 帳號 › iCloud › 管理儲存空間」刪除；WebDAV 資料請在你的 WebDAV 服務中刪除 `AO3Reader` 資料夾。
- **AO3 帳號資料**（書籤、訂閱、Kudos、評論等）屬於 AO3，請在 AO3 網站上管理。

## 聯絡

隱私問題請在 [GitHub Issues](https://github.com/Ferrosophy/yet-another-ao3-reader/issues) 提出；涉及安全漏洞請依 [SECURITY.md](SECURITY.md) 私密回報。

---

## English summary

- No developer server, no account system, no analytics, tracking or ads. The developer receives none of your data.
- Requests go only to the content source you choose (AO3 or a mirror you added), the translation service you choose, and your own iCloud or WebDAV if you enable sync.
- Your AO3 password is sent only to the selected source when you log in. It is never stored or logged; only that site's cookies are kept on the device.
- API keys and the WebDAV password are stored in the device keychain and never synced.
- The debug log stays on the device and hides token and cookie values; it leaves the device only if you copy it.
- Settings › Privacy › "Erase All Local Data" deletes everything stored on the device and closes the app. Synced data lives in your own iCloud or WebDAV and can be deleted there.
