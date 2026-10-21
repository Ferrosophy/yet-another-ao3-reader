<p align="center">
  <img src="docs/icon.png" width="128" alt="YAAO3R">
</p>

<h1 align="center">Yet another AO3 reader（YAAO3R）</h1>

<p align="center">
  原生 iOS 的 Archive of Our Own 阅读器 · Liquid Glass · 沉浸式翻译
</p>

<p align="center">
  <a href="https://github.com/Ferrosophy/yet-another-ao3-reader/releases/latest"><b>下载最新版</b></a> ·
  <a href="https://ferrosophy.github.io/yet-another-ao3-reader/">介绍网页</a> ·
  <a href="https://github.com/Ferrosophy/yet-another-ao3-reader/issues">意见反馈</a>
</p>

<p align="center">
  <a href="README.md">繁體中文</a> · 简体中文 · <a href="README.en.md">English</a>
</p>

---

YAAO3R 是一个用 SwiftUI 打造的 [Archive of Our Own](https://archiveofourown.org)（AO3）第三方阅读器，采用 iOS 26 的 Liquid Glass 设计。你可以浏览、搜索、离线保存作品，并以「原文在上、译文在下」的方式阅读任何语言的同人作品。

> 本 App 为非官方的第三方客户端，与 AO3 及 Organization for Transformative Works（OTW）无关。

## 功能

### 阅读与翻译
- **沉浸式翻译**：不取代原文，每段原文下方显示译文，也可切换为「仅译文」。作品标题、标签、简介与作者注都能翻译，可分别设置在浏览页与阅读页显示哪些。
- **多种翻译服务**：
  - 免密钥：Google、Bing、腾讯交互翻译 TranSmart、火山、百度、有道、搜狗、DeepL 网页版、Apple 翻译（设备上）。
  - 自备 API Key：Google Cloud、Microsoft Azure、DeepL API、OpenAI 兼容服务（OpenAI / DeepSeek / OpenRouter / Groq / 自定义）、Anthropic Claude、Google Gemini。
- **阅读模式**：滚动或翻页（仿真、平滑、覆盖、淡入淡出）；作者注依官网位置显示在章首或章末。
- **外观**：深色模式、主题色、自定义背景（纯色或图片）与文字颜色；字级、字重、行距、段距、字距、上下左右边距；可导入 TTF / OTF 字体，或从 Google Drive、百度网盘导入。

### 浏览与搜索
- **浏览**：最新作品，以及 Kudos、评论、点击排行榜，可依语言等条件筛选。
- **搜索**：作品、标签、用户、合集四种范围，附自动补全建议与搜索记录。
- **详细搜索与筛选**：与 AO3 的 Work Search 及 Sort and Filter 字段一一对应，例如原作、分级、警告、分类、角色、配对、标签包含 / 排除、字数、更新时间、点击、Kudos 等。

### 离线
- 加入「离线」的作品会自动**先下载原文、再翻译**，没有网络也能阅读。原文与目标语言相同时只下载原文。
- 下载失败会自动断点续传；可暂停、重试，或只更新新章节。
- 可分享为 App 产生的双语 EPUB，或官网的 AZW3 / MOBI / PDF / HTML。

### 账号与数据
- **AO3 账号**：登录后可使用收件箱、订阅、阅读记录、稍后阅读、书签，并直接在 App 内加入书签、订阅作品 / 作者 / 系列。
- **本机保存**：不登录也能把书签、稍后阅读、阅读记录、订阅保存在本机，也可从 AO3 导入。
- **同步**：离线清单、阅读进度、阅读时长、偏好与搜索记录，可通过 iCloud 或 WebDAV（例如坚果云）在设备间同步。
- **时长管理**：阅读时长统计，连续阅读一段时间后提醒休息。

### 连接
- **镜像源**：可自行加入与 AO3 结构相同的镜像网址，切换后所有浏览、阅读、登录都改走该来源。**App 不内置、不提供任何镜像网址。**
- **新手引导**：第一次打开时检测能否连上 AO3，连不上时引导你加入镜像源，并推荐可用的翻译服务。
- **人机验证**：遇到 Cloudflare 或 Anubis 验证时自动弹出验证页，通过后自动回到 App。

### 多语言界面
繁体中文（台湾、香港、澳门）、简体中文、English、日本語、한국어、Français、Deutsch、Español、Português (Brasil)、Italiano、Nederlands、Русский、Українська、Polski、Türkçe、Tiếng Việt、ไทย、Bahasa Indonesia、हिन्दी、العربية。

## 安装

- 需要 **iOS 26 或以上**的 iPhone。
- 到 [Releases](https://github.com/Ferrosophy/yet-another-ao3-reader/releases/latest) 下载 `YAAO3R-<版本号>-unsigned.ipa`。
- IPA **未签名**，请用 [AltStore](https://altstore.io)、[SideStore](https://sidestore.io)、[Sideloadly](https://sideloadly.io) 或自己的开发者凭证签名后安装。
- 使用免费 Apple ID 签名时，App 每 7 天需要重新签名一次。

### 在中国大陆使用
AO3 官网在中国大陆通常无法直接连接。第一次打开时的新手引导会检测连接，并教你加入镜像源；之后也可以在「设置 › 内容来源」管理。Google 翻译在中国大陆通常也无法使用，建议改用腾讯、火山或 Bing 翻译。

> 登录时密码会发送给所选的来源，请只使用你信任的镜像。

## 隐私

- App 本身没有账号系统，也没有服务器，不收集任何使用数据。
- AO3 的登录状态以 Cookie 保存在本机，不保存你的密码。
- 翻译 API Key 只存在本机钥匙圈，不会同步到 iCloud；翻译时文本直接送往你选择的翻译服务。
- 同步数据只存放在你自己的 iCloud 或 WebDAV。

## 意见反馈

在 App 的「设置 › 意见反馈」可以直接打开 [GitHub Issues](https://github.com/Ferrosophy/yet-another-ao3-reader/issues)，系统会自动附上版本信息。如果某个镜像源无法使用，在「设置」连点三下「应用版本」可以进入调试页，拷贝记录后一起附上。

喜欢这个项目的话，可以在「设置 › 支持赞助」请开发者喝杯咖啡。

赞助只支持本 App 的开发者，与 AO3 及 OTW 无关，也不会解锁任何功能，所有功能永久免费。如果想支持 AO3 本身，请前往 [OTW 官网](https://www.transformativeworks.org)捐款。

## 已知问题

- IPA 未签名，需要自行签名；使用免费 Apple ID 签名时每 7 天需重新签名一次。
- 只支持 iOS 26 或以上。
- 部分镜像站的防护（Cloudflare 或 Anubis）可能让 App 的请求在验证后仍被拒绝，此时请换用其他镜像。
- 免密钥的翻译服务属于非官方接口，可能限流或暂时失效。
- 评论目前只能阅读与翻译，发表评论需到原网站。
- 翻页模式下，文末的 Kudos 与评论面板需在最后一页继续往后翻才会出现。
- 部分新加入的接口文本，在中文与英文以外的语言中暂时以英文显示。

## 备份与迁移

- **换新设备**：在旧设备打开「设置 › 数据同步」（iCloud 或 WebDAV），新设备选择相同的同步方式后，即可取回离线清单、阅读进度、阅读时长、偏好设置、搜索记录与本机保存的书签等数据。
- **离线文件**不会同步：新设备会依离线清单自动重新下载。已导出的 EPUB 等文件可在「文件」App 的 YAAO3R › Bookshelf 中另行备份。
- **不会同步的数据**：翻译服务的 API Key、导入的字体与背景图片、翻译缓存与 AO3 登录状态，换机后需要重新设置或登录。
- App 的本机数据也会包含在 iPhone 的 iCloud 备份或电脑备份中，从备份还原时一并恢复（翻译缓存除外）。

## 疑难排解

- **连不上 AO3**：在「设置 › 内容来源」加入你信任的镜像源；遇到人机验证时照画面完成即可。
- **AO3 暂时限制访问（HTTP 429）**：App 会停止重试并显示需要等待的时间，请稍后再试。
- **页面读取失败或内容不完整**：可能是 AO3 改版。请在「设置」连点三下「应用版本」打开调试页，拷贝记录后到 Issues 回报，我们会更新解析规则。已离线保存的作品不受影响。
- **翻译失败**：到「设置 › 翻译服务」换用其他服务（例如设备上的 Apple 翻译）；不翻译时原文阅读不受影响。
- **离线阅读**不需要网络；书架上已下载的作品随时可读。

## 隐私与安全

- [隐私政策](PRIVACY.md)：数据流向与删除方式。
- [安全政策](SECURITY.md)：请通过 GitHub 的私密回报功能回报安全漏洞，不要公开发布。
- [更新日志](CHANGELOG.md)

## 开发

需要 Xcode 26 以上与 iOS 26 SDK。

```bash
brew install xcodegen
xcodegen generate
open AO3Reader.xcodeproj
```

- 相依套件：[SwiftSoup](https://github.com/scinfu/SwiftSoup)（Swift Package Manager，用于解析 HTML）。
- 架构与需求规格见 [SPEC.md](SPEC.md)；界面多语系的产生流程见 [scripts/l10n](scripts/l10n/README.md)。

```
AO3Reader/
├── App/            进入点、分页、全域状态
├── Models/         作品、章节、段落、搜索条件
├── Core/           网络（AO3Client、来源、调试记录）、解析（AO3Parser）、登录、离线、保存与同步
├── Translation/    翻译服务、缓存、设置
└── Features/       浏览、搜索、阅读、离线、账号、设置、新手引导
```

### 云端建置

`.github/workflows/build-ipa.yml` 会在 GitHub Actions 的 macOS runner 上产生**未签名** IPA：

| 触发方式 | 版本号 | 产物 |
| --- | --- | --- |
| 推送 main / PR | `project.yml` 的 `MARKETING_VERSION` | Artifact |
| 手动运行（可填版本号） | 输入的版本号 | Artifact；勾选「发行」时另建 GitHub Release |
| 推送 tag `v1.2.3` | `1.2.3` | Artifact + GitHub Release |

IPA 文件名为 `YAAO3R-<版本号>-unsigned.ipa`。

## 注意事项

- 请遵守 AO3 的[服务条款](https://archiveofourown.org/tos)。App 只在你操作时加载页面，遇到 HTTP 429 会停止重试并显示等待时间。
- 免密钥的翻译服务属于非官方界面，可能限流或变更；需要稳定时建议使用自备 API Key 的服务。
- 作品的著作权属于原作者。请勿把离线或导出的作品与译文再散布。
