## YAFR 1.0.4

App 更名为 **Yet another fanfic reader（YAFR）**，仍是非官方的 AO3 阅读器。这是 1.0.0 之后的第一个正式更新。

**尊重作者**
- 作者声明「不要翻译 / No AI」的作品默认不翻译，且不会使用 AI 翻译服务。
- 仅限登录用户阅读的作品不提供导出与分享。
- 后台检查更新与送 Kudos 不再增加作品的点击数。

**阅读**
- 「在网页中打开」：使用镜像时打开镜像站。
- 阅读进度百分比：点击可输入数字跳到指定进度。
- 每章末尾内嵌「Kudos」与「评论」按钮及支持作者的提示；已给过 Kudos 时再次点击会提示。
- 评论按讨论串显示回复关系，标示作者本人的评论，支持沉浸式翻译。

**浏览**
- 所有作品列表新增快速跳转：点击卡片右下角的圆形序号按钮，输入数字即可跳到对应作品。
- 作品卡片上的译文颜色加深，更易阅读。
- 修复切换来源或分页后，浏览页有时显示加载失败、需要重开 App 的问题。

**安全与隐私**
- 镜像源只接受 HTTPS；通过镜像登录前会提示风险。
- 调试记录自动隐藏 Cookie、令牌与敏感信息，拷贝前提醒不要公开发布。
- 第一次开启云端翻译时，提示文本会发送给第三方翻译服务。
- 设置 › 隐私：新增「清除所有本地数据」。
- 双语 EPUB 附上作品出处与版权提示。
- 离线下载遇到 AO3 限流时整个队列暂停等待；批量下载每 3 天最多 50 部。
- 识别镜像站的 ALTCHA 人机验证，修复部分镜像验证后仍无法访问的问题。

**其他**
- 不再使用 AO3 官方标志；更新赞助页说明。
- 项目以 GPL-3.0-or-later 许可证开源；仓库更名为 yet-another-fanfic-reader。

**安装**
- 需要 iOS 26 或以上。
- 下方的 IPA **未签名**，请用 AltStore、SideStore、Sideloadly 或自己的开发者证书签名后安装。
- 完整更新记录见 [CHANGELOG.md](https://github.com/Ferrosophy/yet-another-fanfic-reader/blob/main/CHANGELOG.md)。

---

**繁體中文**：App 更名為 YAFR。新增「在網頁中打開」、閱讀進度百分比與跳轉、章末 Kudos 與評論（含沉浸式翻譯）、作品列表快速跳轉、「清除所有本地資料」；尊重作者「不要翻譯 / No AI」的聲明；鏡像只接受 HTTPS；修正切換來源後瀏覽頁載入失敗的問題。需要 iOS 26 或以上；IPA 未簽名，需自行簽名後安裝。

**English**: The app is renamed YAFR. Adds Open in Browser, a reading progress percentage with jump-to-progress, end-of-chapter kudos and comments (with immersive translation), quick jump in all work lists and Erase All Local Data. Respects authors' "do not translate / No AI" wishes, accepts only HTTPS mirrors, and fixes the browse page sometimes failing to load after switching sources. Requires iOS 26 or later; the IPA is unsigned and must be signed before installing.

YAFR 是独立开发的非官方 AO3 阅读器，与 AO3 及 OTW 没有官方关联。
