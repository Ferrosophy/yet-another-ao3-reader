# 隐私政策 / Privacy Policy

最后更新：2026-10-21 · 适用于 YAAO3R（Yet another AO3 reader）1.0 及以上版本

YAAO3R 是独立开发的非官方 AO3 阅读器，与 Archive of Our Own（AO3）及 Organization for Transformative Works（OTW）没有官方关联。

## 我们不收集任何数据

- App **没有开发者服务器**、没有账号系统，也**没有任何分析、追踪或广告 SDK**。
- 开发者收不到你的阅读内容、搜索记录、账号或任何使用数据。

## 数据会传到哪里

| 数据 | 发送对象 | 说明 |
| --- | --- | --- |
| 浏览、搜索、阅读的请求 | 你选择的内容来源（AO3 官网或你自行加入的镜像） | 与用浏览器浏览该网站相同。 |
| AO3 账号与密码 | 只在登录时送往你选择的内容来源 | **密码不会保存**，也不会写入调试记录。登录后只在本机保存该网站的 Cookie。使用镜像登录时密码会送往镜像站，请只使用你信任的镜像。 |
| 要翻译的文本 | 你选择的翻译服务（Google、Bing、腾讯、火山、DeepL、OpenAI 兼容服务、Claude、Gemini 等） | 只送出需要翻译的段落、标题、简介或评论。各服务如何处理数据请参考其隐私政策。Apple 翻译在设备上进行。 |
| 翻译服务的 API Key | 只送往对应的翻译服务 | 保存在设备钥匙圈（仅此设备、不同步 iCloud）。 |
| 同步数据（离线清单、阅读进度、阅读时长、偏好、搜索记录、本机书签等） | 你自己的 iCloud 或 WebDAV（例如坚果云） | 默认不打开。WebDAV 密码保存在钥匙圈。不包含 API Key。 |

## 保存在设备上的数据

设置、离线作品与导出档（「文件」App 的 YAAO3R › Bookshelf）、书架、阅读记录与进度、翻译缓存、导入的字体与背景图、登录 Cookie、调试记录。

调试记录（设置 › 连点版本号三次）只保存在本机，记录请求网址、状态与部分回应内容；验证权杖与 Cookie 的值会被隐藏。只有你主动拷贝时才会离开设备。

## 删除数据

- **App 内**：设置 › 隐私 ›「清除所有本地数据」会删除上述所有本机数据、钥匙圈中的 API Key 与密码、Cookie 与网页数据，完成后 App 会关闭。
- **只清除翻译缓存**：设置 › 隐私 ›「清除翻译缓存」。
- **卸载**：删除 App 即删除所有本机数据（钥匙圈项目可能由系统保留，建议先使用「清除所有本地数据」）。
- **同步数据**：存放在你自己的 iCloud 或 WebDAV。iCloud 数据可在 iPhone「设置 › Apple 账号 › iCloud › 管理保存空间」删除；WebDAV 数据请在你的 WebDAV 服务中删除 `AO3Reader` 文件夹。
- **AO3 账号数据**（书签、订阅、Kudos、评论等）属于 AO3，请在 AO3 网站上管理。

## 联系

隐私问题请在 [GitHub Issues](https://github.com/Ferrosophy/yet-another-ao3-reader/issues) 提出；涉及安全漏洞请依 [SECURITY.md](SECURITY.md) 私密回报。

---

## English summary

- No developer server, no account system, no analytics, tracking or ads. The developer receives none of your data.
- Requests go only to the content source you choose (AO3 or a mirror you added), the translation service you choose, and your own iCloud or WebDAV if you enable sync.
- Your AO3 password is sent only to the selected source when you log in. It is never stored or logged; only that site's cookies are kept on the device.
- API keys and the WebDAV password are stored in the device keychain and never synced.
- The debug log stays on the device and hides token and cookie values; it leaves the device only if you copy it.
- Settings › Privacy › "Erase All Local Data" deletes everything stored on the device and closes the app. Synced data lives in your own iCloud or WebDAV and can be deleted there.
