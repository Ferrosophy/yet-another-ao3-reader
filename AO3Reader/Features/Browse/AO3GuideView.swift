import SwiftUI

/// AO3 術語與使用說明（依官網 FAQ 與 Terms 整理）。繁體中文與英文為原稿，
/// 其他介面語言由 `scripts/l10n/guide.py` 產生於 AO3Guide.json；預設顯示目前介面語言的版本，術語附英文原文。
struct AO3GuideView: View {
    struct Entry: Identifiable, Decodable {
        let term: String
        let detail: String
        var id: String { term }
    }

    struct Topic: Identifiable, Decodable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var language = AO3GuideView.defaultLanguage
    @State private var search = ""

    /// 其他語言版本（機器翻譯自英文版）
    private static let translations: [String: [Topic]] = {
        guard let url = Bundle.main.url(forResource: "AO3Guide", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [:] }
        return (try? JSONDecoder().decode([String: [Topic]].self, from: data)) ?? [:]
    }()

    /// 可選的版本：代碼與顯示名稱（與介面語言清單一致，繁體中文各地區共用一個版本）
    private static var languages: [(code: String, name: String)] {
        var result: [(code: String, name: String)] = [(code: "zh-Hant", name: "繁體中文"), (code: "en", name: "English")]
        for language in InterfaceLanguage.all where translations[language.code] != nil {
            result.append((code: language.code, name: language.name))
        }
        return result
    }

    private static var defaultLanguage: String {
        let code = InterfaceLanguage.currentCode
        if code.hasPrefix("zh-Hant") || code == "zh-TW" || code == "zh-HK" { return "zh-Hant" }
        if code.hasPrefix("zh") { return translations["zh-Hans"] == nil ? "zh-Hant" : "zh-Hans" }
        if translations[code] != nil { return code }
        let base = String(code.prefix { $0 != "-" })
        if base == "pt", translations["pt-BR"] != nil { return "pt-BR" }
        return translations[base] != nil ? base : "en"
    }

    private var topics: [Topic] {
        switch language {
        case "zh-Hant": Self.chinese
        case "en": Self.english
        default: Self.translations[language] ?? Self.english
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredTopics) { topic in
                    Section {
                        ForEach(topic.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: entry.term).appFont(.headline)
                                Text(verbatim: entry.detail)
                                    .appFont(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(verbatim: topic.title)
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("AO3 說明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("語言", selection: $language) {
                            ForEach(Self.languages, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                        }
                    } label: {
                        Label("語言", systemImage: "globe")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var filteredTopics: [Topic] {
        guard !search.isEmpty else { return topics }
        return topics.compactMap { topic in
            let entries = topic.entries.filter {
                $0.term.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)
            }
            return entries.isEmpty ? nil : Topic(title: topic.title, entries: entries)
        }
    }

    // MARK: - 中文

    static let chinese: [Topic] = [
        Topic(title: "認識 AO3", entries: [
            Entry(term: "AO3（Archive of Our Own）", detail: "由非營利組織 OTW（Organization for Transformative Works）營運的同人作品存檔庫，沒有廣告，作品版權屬於作者。本 App 是非官方的第三方閱讀器。"),
            Entry(term: "帳號與邀請", detail: "AO3 需要邀請才能註冊：在官網加入邀請佇列（Invitation Queue），收到邀請信後註冊。未登入也能閱讀大部分作品，但「僅限登入用戶」的作品、書籤、訂閱、Kudos 等需要登入。"),
            Entry(term: "Pseud（筆名）", detail: "同一帳號可以有多個筆名，作品署名顯示的是筆名，括號內才是帳號名稱。"),
        ]),
        Topic(title: "作品資訊", entries: [
            Entry(term: "Kudos", detail: "類似「喜歡」，每個人對同一作品只能給一次，訪客也可以給。"),
            Entry(term: "Hits（點擊）", detail: "作品被開啟的次數，同一人重複開啟可能被重複計算，只能作為熱度參考。"),
            Entry(term: "Bookmarks（書籤）", detail: "收藏作品，可附備註與自己的標籤，可設為私人；公開書籤也是讀者推薦作品的方式。"),
            Entry(term: "Chapters 3/?", detail: "已發佈章數 / 預計總章數。「?」表示作者未定總章數；兩數相同代表完結（Complete）。"),
            Entry(term: "WIP / Complete", detail: "連載中（Work in Progress）／已完結。"),
            Entry(term: "Series（系列）", detail: "作者把多部相關作品串成系列，可訂閱整個系列。"),
            Entry(term: "Collections（合集）", detail: "依主題、活動或交換活動（Gift Exchange、Prompt Meme）收錄的作品集合，例如 Yuletide。"),
            Entry(term: "Restricted（僅限登入）", detail: "作者設定只有登入用戶才能閱讀的作品，未登入時會顯示需要登入。"),
            Entry(term: "Orphan（孤兒作品）", detail: "作者放棄所有權後轉到 orphan_account 帳號名下的作品。"),
            Entry(term: "Anonymous（匿名）", detail: "在匿名合集中發佈、暫時隱藏作者身份的作品。"),
        ]),
        Topic(title: "分級 Rating", entries: [
            Entry(term: "G — General Audiences", detail: "適合所有年齡。"),
            Entry(term: "T — Teen And Up Audiences", detail: "適合 13 歲以上。"),
            Entry(term: "M — Mature", detail: "含成人主題，但不如 Explicit 露骨。"),
            Entry(term: "E — Explicit", detail: "含露骨的性或暴力等成人內容。"),
            Entry(term: "Not Rated", detail: "作者未選擇分級，內容可能包含任何程度。"),
        ]),
        Topic(title: "警告 Archive Warnings", entries: [
            Entry(term: "Creator Chose Not To Use Archive Warnings", detail: "作者選擇不標警告，內容可能包含任何警告項目，請自行斟酌。"),
            Entry(term: "No Archive Warnings Apply", detail: "不含以下四項主要警告（但仍可能有其他敏感內容，請看其他標籤）。"),
            Entry(term: "Graphic Depictions Of Violence", detail: "露骨的暴力描寫。"),
            Entry(term: "Major Character Death", detail: "主要角色死亡。"),
            Entry(term: "Rape/Non-Con", detail: "強迫性行為描寫。"),
            Entry(term: "Underage Sex", detail: "涉及未成年人的性描寫。"),
        ]),
        Topic(title: "分類 Category", entries: [
            Entry(term: "F/F、F/M、M/M", detail: "女女、男女、男男的戀愛或性關係。"),
            Entry(term: "Gen", detail: "General，沒有戀愛或性關係為主軸，或關係不是重點。"),
            Entry(term: "Multi", detail: "包含多種關係類型。"),
            Entry(term: "Other", detail: "其他類型的關係。"),
        ]),
        Topic(title: "標籤 Tags", entries: [
            Entry(term: "Fandom", detail: "作品所屬的原作，例如某部小說、動畫或電影。跨多個原作的作品稱為 Crossover。"),
            Entry(term: "Relationship（配對）", detail: "「A/B」表示戀愛或性關係；「A & B」表示友情、親情等非戀愛關係。斜線前後順序通常沒有攻受含義。"),
            Entry(term: "Characters", detail: "作品中出現的角色。"),
            Entry(term: "Additional Tags（其他標籤）", detail: "作者自由填寫的標籤（Freeform），描述題材、劇情元素或附註，例如 Fluff、Angst、Hurt/Comfort、Alternate Universe。"),
            Entry(term: "正式標籤（Canonical）與標籤整理", detail: "AO3 志工（Tag Wranglers）會把同義的標籤合併到一個正式標籤下，所以點進某個標籤時也會看到使用同義寫法的作品。"),
            Entry(term: "Fluff / Angst / Hurt/Comfort", detail: "溫馨甜文／虐文／受傷與安慰。"),
            Entry(term: "AU（Alternate Universe）", detail: "平行世界設定，把角色放進與原作不同的背景，例如 Coffee Shop AU、Modern AU。"),
            Entry(term: "Reader / You", detail: "以讀者（你）為主角之一的作品（Reader-Insert）。"),
        ]),
        Topic(title: "搜尋與篩選", entries: [
            Entry(term: "作品搜尋", detail: "可同時以關鍵字、標題、作者、Fandom、分級、警告、分類、角色、配對、標籤、字數、語言、Kudos 等條件搜尋，結果由 AO3 官網產生。"),
            Entry(term: "數值與日期語法", detail: "字數、Kudos、點擊等可用「> 1000」「< 500」「100-500」；更新時間可用「< 7 days」「> 1 year」。"),
            Entry(term: "標籤頁篩選", detail: "進入某個標籤後，可再「包含」或「排除」其他標籤，並依分級、完結狀態、字數、語言等篩選。"),
            Entry(term: "排除標籤", detail: "不想看的題材可以加入排除標籤，例如排除某個配對或 Major Character Death。"),
            Entry(term: "排行榜", detail: "本 App 的 Kudos／評論／點擊排行以官網搜尋排序產生，時間範圍以作品最後更新時間計算。"),
        ]),
        Topic(title: "帳號功能", entries: [
            Entry(term: "稍後閱讀（Marked for Later）", detail: "把作品存到待讀清單，讀完可標記為已讀。需要在官網偏好設定中開啟閱讀紀錄。"),
            Entry(term: "閱讀紀錄（History）", detail: "登入後瀏覽過的作品會記錄在帳號中。"),
            Entry(term: "訂閱（Subscriptions）", detail: "訂閱作品、系列或作者後，有更新時 AO3 會寄送電子郵件通知。"),
            Entry(term: "收件匣（Inbox）", detail: "別人對你作品或評論的回覆會出現在這裡。"),
            Entry(term: "評論（Comments）", detail: "可針對章節留言；作者可選擇審核或關閉評論。"),
        ]),
        Topic(title: "本 App 的使用", entries: [
            Entry(term: "沉浸式翻譯", detail: "閱讀頁點翻譯按鈕，譯文會顯示在每段原文下方；長按翻譯按鈕可開啟翻譯設定。翻譯只在本機進行，API Key 只存在這台裝置。"),
            Entry(term: "鏡像來源", detail: "設定 → 內容來源可加入鏡像網址；登入狀態依來源分開保存，請只在信任的鏡像登入。"),
            Entry(term: "禮儀", detail: "喜歡的作品可以留 Kudos 或評論支持作者；不要把作品轉載到其他網站或用於 AI 訓練。"),
        ]),
    ]

    // MARK: - English

    static let english: [Topic] = [
        Topic(title: "About AO3", entries: [
            Entry(term: "AO3 (Archive of Our Own)", detail: "A nonprofit fanwork archive run by the Organization for Transformative Works (OTW). It has no ads, and creators keep the rights to their works. This app is an unofficial third-party reader."),
            Entry(term: "Accounts & invitations", detail: "Registration needs an invitation: join the Invitation Queue on the website and sign up when the email arrives. Most works can be read without logging in, but restricted works, bookmarks, subscriptions and history need an account."),
            Entry(term: "Pseud", detail: "A pen name. One account can have several; bylines show the pseud, with the account name in parentheses when different."),
        ]),
        Topic(title: "Work Info", entries: [
            Entry(term: "Kudos", detail: "Like a “like”. Each person can leave kudos on a work once; guests can too."),
            Entry(term: "Hits", detail: "How many times a work was opened. Repeat visits may count more than once, so treat it as a rough measure of popularity."),
            Entry(term: "Bookmarks", detail: "Save a work with your own notes and tags, publicly or privately. Public bookmarks also work as recommendations."),
            Entry(term: "Chapters 3/?", detail: "Posted chapters / planned total. “?” means the total isn't set; equal numbers mean the work is complete."),
            Entry(term: "WIP / Complete", detail: "Work in progress / finished."),
            Entry(term: "Series", detail: "Related works grouped by the creator. You can subscribe to a whole series."),
            Entry(term: "Collections", detail: "Groups of works for a theme or event, including challenges like gift exchanges and prompt memes (e.g. Yuletide)."),
            Entry(term: "Restricted", detail: "Works the creator has limited to logged-in users."),
            Entry(term: "Orphaned works", detail: "Works whose creators gave up ownership; they now belong to orphan_account."),
            Entry(term: "Anonymous", detail: "Works posted to an anonymous collection, with the creator's name hidden for now."),
        ]),
        Topic(title: "Ratings", entries: [
            Entry(term: "G — General Audiences", detail: "Suitable for all ages."),
            Entry(term: "T — Teen And Up Audiences", detail: "Suitable for ages 13 and up."),
            Entry(term: "M — Mature", detail: "Adult themes, less graphic than Explicit."),
            Entry(term: "E — Explicit", detail: "Graphic sexual content, violence or other adult content."),
            Entry(term: "Not Rated", detail: "The creator didn't choose a rating; the work could contain anything."),
        ]),
        Topic(title: "Archive Warnings", entries: [
            Entry(term: "Creator Chose Not To Use Archive Warnings", detail: "The work may contain any of the warnings. Read at your own discretion."),
            Entry(term: "No Archive Warnings Apply", detail: "None of the four main warnings apply. Other sensitive content may still be tagged elsewhere."),
            Entry(term: "Graphic Depictions Of Violence", detail: "Graphic violence."),
            Entry(term: "Major Character Death", detail: "A main character dies."),
            Entry(term: "Rape/Non-Con", detail: "Non-consensual sexual content."),
            Entry(term: "Underage Sex", detail: "Sexual content involving minors."),
        ]),
        Topic(title: "Categories", entries: [
            Entry(term: "F/F, F/M, M/M", detail: "Romantic or sexual relationships between women, a woman and a man, or men."),
            Entry(term: "Gen", detail: "General: no romantic or sexual relationship as the focus."),
            Entry(term: "Multi", detail: "More than one type of relationship."),
            Entry(term: "Other", detail: "Other types of relationships."),
        ]),
        Topic(title: "Tags", entries: [
            Entry(term: "Fandom", detail: "The source the work is based on. Works spanning several fandoms are crossovers."),
            Entry(term: "Relationships", detail: "“A/B” is a romantic or sexual relationship; “A & B” is platonic (friendship, family). The order of names usually doesn't imply roles."),
            Entry(term: "Characters", detail: "Characters who appear in the work."),
            Entry(term: "Additional Tags", detail: "Freeform tags for tropes, themes and notes, such as Fluff, Angst, Hurt/Comfort or Alternate Universe."),
            Entry(term: "Canonical tags & wrangling", detail: "Volunteer tag wranglers link synonyms to one canonical tag, so a tag page also shows works that used other spellings."),
            Entry(term: "Fluff / Angst / Hurt/Comfort", detail: "Sweet and light / emotionally painful / one character hurt and another comforting them."),
            Entry(term: "AU (Alternate Universe)", detail: "Characters placed in a setting different from canon, e.g. Coffee Shop AU or Modern AU."),
            Entry(term: "Reader / You", detail: "Reader-insert works where “you” are one of the characters."),
        ]),
        Topic(title: "Searching & Filtering", entries: [
            Entry(term: "Work search", detail: "Search by keywords, title, creator, fandom, rating, warnings, category, characters, relationships, tags, word count, language, kudos and more. Results come straight from AO3."),
            Entry(term: "Numbers & dates", detail: "Use “> 1000”, “< 500” or “100-500” for counts, and “< 7 days” or “> 1 year” for dates."),
            Entry(term: "Filtering a tag", detail: "On a tag's works, include or exclude more tags and filter by rating, completion, word count, language and so on."),
            Entry(term: "Excluding tags", detail: "Exclude things you don't want to see, like a relationship or Major Character Death."),
            Entry(term: "Charts", detail: "This app's kudos, comments and hits charts use AO3's search sorting; time ranges are based on each work's last update."),
        ]),
        Topic(title: "Account Features", entries: [
            Entry(term: "Marked for Later", detail: "A to-read list; mark works as read when you're done. Requires history to be enabled in your AO3 preferences."),
            Entry(term: "History", detail: "Works you open while logged in are recorded on your account."),
            Entry(term: "Subscriptions", detail: "Subscribe to a work, series or creator to get email updates when they post."),
            Entry(term: "Inbox", detail: "Comments and replies on your works and comments appear here."),
            Entry(term: "Comments", detail: "Leave comments on chapters. Creators can moderate or disable comments."),
        ]),
        Topic(title: "Using This App", entries: [
            Entry(term: "Immersive translation", detail: "Tap the translate button while reading to show a translation under each paragraph. Touch and hold it to open translation settings. API keys stay on this device."),
            Entry(term: "Mirror sources", detail: "Add mirrors in Settings → Content Source. Logins are kept per source; only log in on mirrors you trust."),
            Entry(term: "Etiquette", detail: "Leave kudos or comments to support creators. Don't repost works elsewhere or use them for AI training."),
        ]),
    ]
}
