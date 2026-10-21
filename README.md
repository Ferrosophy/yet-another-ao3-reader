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
  简体中文 · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.en.md">English</a>
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

需要 **iOS 26 或以上**的 iPhone。目前只通过本仓库的 GitHub Releases 发布，尚未上架 App Store 或 TestFlight。

1. 到 [Releases](https://github.com/Ferrosophy/yet-another-ao3-reader/releases/latest) 下载 `YAAO3R-<版本号>-unsigned.ipa`。
2. **核对校验值**：Release 说明里附有 SHA-256，也可下载同名的 `.sha256` 文件。在电脑上执行 `shasum -a 256 YAAO3R-<版本号>-unsigned.ipa`（macOS / Linux）或 `Get-FileHash YAAO3R-<版本号>-unsigned.ipa`（Windows PowerShell），结果应与 Release 中的一致。
3. **签名并安装**：IPA 未签名，需要用以下任一工具以你自己的 Apple ID 签名后安装：
   - [AltStore](https://altstore.io) 或 [SideStore](https://sidestore.io)：在 iPhone 上安装后，用它打开 IPA 即可；
   - [Sideloadly](https://sideloadly.io)：在电脑上连接 iPhone，拖入 IPA 并登录 Apple ID；
   - 自己的付费开发者证书。
4. 第一次打开前，到 iPhone「设置 › 通用 › VPN 与设备管理」信任你的开发者证书；iOS 16 以上还需要在「设置 › 隐私与安全性」开启「开发者模式」。

**限制与风险**
- 使用免费 Apple ID 签名时，App 每 **7 天**需要重新签名一次（AltStore / SideStore 可在后台自动续签），而且同时最多只能安装 3 个自行签名的 App。
- 签名工具需要你的 Apple ID，请使用你信任的工具，建议另外开一个 Apple ID 专门用来签名。
- **只从本仓库的 Releases 下载 IPA。** 第三方「二次打包」或「免签」版本可能被植入恶意代码，或窃取你的 AO3 账号与 API Key；本项目不对非官方来源的安装包负责。
- 升级时直接安装新版 IPA 即可，本机数据会保留（使用同一个 Apple ID 签名）。

### 在中国大陆使用
AO3 官网在中国大陆通常无法直接连接。第一次打开时的新手引导会检测连接，并教你加入镜像源；之后也可以在「设置 › 内容来源」管理。Google 翻译在中国大陆通常也无法使用，建议改用腾讯、火山或 Bing 翻译。

> **使用镜像登录有风险**：镜像站不是 AO3 官方网站，镜像的运营者能看到你输入的账号与密码，以及登录后账号里的内容。App 的「测试连接」只检查页面格式是否兼容，不代表镜像安全可信。请尽量在官网登录，或只使用你信任的镜像，并避免使用与其他网站相同的密码。App 只接受 HTTPS 镜像。

## 隐私

- App 本身没有账号系统，也没有服务器，不收集任何使用数据。
- AO3 的登录状态以 Cookie 保存在本机，不保存你的密码。
- 翻译 API Key 只存在本机钥匙圈，不会同步到 iCloud；翻译时文本直接送往你选择的翻译服务。
- 同步数据只存放在你自己的 iCloud 或 WebDAV。

## 翻译服务说明

- **数据会发送给服务商**：开启翻译后，要翻译的文本（正文、标题、标签、简介、作者注与评论）会发送到你选择的翻译服务，并按该服务的隐私政策处理。**只有 Apple 翻译在设备上进行**，文字不会离开你的 iPhone。第一次在阅读页开启云端翻译时，App 也会提示这一点。
- **非官方接口**：标示「免密钥」或「网页版」的服务（Google、Bing、腾讯 TranSmart、火山、百度、有道、搜狗、未填密钥的 DeepL）使用的是网页端的非官方接口，**未经服务商授权**，可能违反其服务条款、被限流或随时失效。需要稳定、合规的使用时，请改用官方 API（Google Cloud Translation、Microsoft Azure、DeepL API、OpenAI 兼容服务、Claude、Gemini 等，需自备 API Key）或 Apple 翻译。
- **翻译准确性**：机器翻译可能有误，不能取代原文。标签、警告（Archive Warnings）与作者注尤其请以原文为准。

## 意见反馈与维护

- **Bug 与功能建议**：在 App 的「设置 › 意见反馈」可以直接打开 [GitHub Issues](https://github.com/Ferrosophy/yet-another-ao3-reader/issues) 的问题回报表单，会自动带上版本信息；功能建议请选「功能建议」模板。
- **安全漏洞**：请勿公开，使用 Security 页面的私密回报，详见 [SECURITY.md](SECURITY.md)。
- **作者内容异议**：如果你是 AO3 作者，对作品在本 App 中的显示、翻译或离线保存有疑虑，请使用「作者内容异议」模板。本 App 不托管、不转载任何作品；作品可在 AO3 设置为仅限登录用户阅读，本 App 会遵守此限制。
- **调试记录**：如果某个镜像源无法使用，在「设置」连点三下「应用版本」可以进入调试页。记录已隐藏密码、Cookie 与验证令牌，但仍包含浏览过的网址，请私下提供，不要公开贴出。
- **维护预期**：这是个人业余维护的项目，会尽量回复与修复，但无法保证响应时间或实现所有建议。AO3 改版时可能需要一段时间才能适配。

喜欢这个项目的话，可以在「设置 › 支持赞助」请开发者喝杯咖啡。

赞助只支持本 App 的开发者，与 AO3 及 OTW 无关，也不会解锁任何功能，所有功能永久免费。如果想支持 AO3 本身，请前往 [OTW 官网](https://www.transformativeworks.org)捐款。

## 已知问题

- IPA 未签名，需要自行签名；使用免费 Apple ID 签名时每 7 天需重新签名一次。
- 只支持 iOS 26 或以上。
- 部分镜像站的防护（Cloudflare 或 Anubis）可能让 App 的请求在验证后仍被拒绝，此时请换用其他镜像。
- 免密钥的翻译服务属于非官方接口，可能限流或暂时失效。
- 评论目前只能阅读与翻译，发表评论需到原网站。
- 部分新加入的界面文本，在中文与英文以外的语言中暂时以英文显示。

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

## 许可证

本项目以 [GNU 通用公共许可证](LICENSE)第 3 版或（由你选择的）任何更新的版本开源（SPDX：`GPL-3.0-or-later`），每个源代码文件开头都有相同的声明。你可以自由使用、修改和再发布，但再发布（包括修改后的版本）时必须以相同的许可证公开源代码。第三方依赖 [SwiftSoup](https://github.com/scinfu/SwiftSoup) 采用 MIT 许可证。

## 开发

### 版本与更新

- 版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)：`主版本.次版本.修订号`。不兼容的变更增加主版本，新功能增加次版本，修复与小改动增加修订号。
- 每个版本的变更记录在 [CHANGELOG.md](CHANGELOG.md)，已知问题列在上方「已知问题」。
- 正式版发布在 GitHub Releases，并附上 IPA 的 SHA-256 校验值。

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
