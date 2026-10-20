import Foundation
import Testing
@testable import AO3Reader

struct WorkSearchQueryTests {
    @Test func encodesOfficialSearchParameters() {
        var query = WorkSearchQuery()
        query.query = "coffee shop"
        query.rating = .teen
        query.warnings = [.noneApply]
        query.completion = .yes
        query.sortColumn = .kudos

        let items = Dictionary(query.queryItems(page: 2).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        #expect(items["work_search[query]"] == "coffee shop")
        #expect(items["work_search[rating_ids]"] == "11")
        #expect(items["work_search[archive_warning_ids][]"] == "16")
        #expect(items["work_search[complete]"] == "T")
        #expect(items["work_search[sort_column]"] == "kudos_count")
        #expect(items["page"] == "2")
    }
}

struct AO3ParserTests {
    @Test func parsesBlurbsAndPagination() throws {
        let html = """
        <ol class="work index group">
          <li id="work_123" class="work blurb group">
            <div class="header module">
              <h4 class="heading"><a href="/works/123">A Title</a> by <a rel="author" href="/users/someone/pseuds/someone">someone</a></h4>
              <h5 class="fandoms heading"><a class="tag" href="/tags/X/works">Fandom X</a></h5>
              <ul class="required-tags"><li><span class="rating-teen rating" title="Teen And Up Audiences"></span></li></ul>
              <p class="datetime">01 Oct 2026</p>
            </div>
            <blockquote class="userstuff summary"><p>Summary here.</p></blockquote>
            <dl class="stats"><dd class="words">1,234</dd><dd class="kudos">56</dd></dl>
          </li>
        </ol>
        <ol class="pagination"><li class="next"><a href="?page=2">Next</a></li></ol>
        """
        let page = try AO3Parser.workPage(html: html, page: 1)
        #expect(page.hasNextPage)
        let work = try #require(page.works.first)
        #expect(work.id == 123)
        #expect(work.title == "A Title")
        #expect(work.authors == ["someone"])
        #expect(work.fandoms == ["Fandom X"])
        #expect(work.rating == "Teen And Up Audiences")
        #expect(work.words == "1,234")
    }

    @Test func splitsChapterIntoParagraphs() throws {
        let html = """
        <div id="workskin"><div class="preface group"><h2 class="title heading">T</h2></div>
        <div id="chapters">
          <div class="userstuff">
            <h3 class="landmark heading">Work Text:</h3>
            <p>First line<br>second line</p>
            <hr>
            <p>Second paragraph.</p>
          </div>
        </div></div>
        """
        let detail = try AO3Parser.workDetail(html: html, id: 1)
        let paragraphs = try #require(detail.chapters.first).paragraphs
        #expect(paragraphs.map(\.kind) == [.body, .separator, .body])
        #expect(paragraphs[0].text == "First line\nsecond line")
        #expect(paragraphs[2].text == "Second paragraph.")
    }

    @Test func detectsLoggedInUser() {
        let html = #"<ul id="greeting"><li class="dropdown"><a class="dropdown-toggle" href="/users/reader42">Hi, reader42!</a></li></ul>"#
        #expect(AO3Parser.loggedInUsername(html) == "reader42")
    }
}

struct LLMPromptTests {
    @Test func parsesFencedJSONArray() throws {
        let output = "```json\n[\"你好\", \"世界\"]\n```"
        #expect(try LLMPrompt.parse(output, expectedCount: 2) == ["你好", "世界"])
    }

    @Test func rejectsCountMismatch() {
        #expect(throws: TranslationError.self) {
            try LLMPrompt.parse(#"["only one"]"#, expectedCount: 2)
        }
    }
}

struct SourceStoreTests {
    @Test func normalizesMirrorURLs() {
        #expect(SourceStore.normalize("mirror.example.org/works?x=1")?.absoluteString == "https://mirror.example.org")
        #expect(SourceStore.normalize("ftp://nope") == nil)
        #expect(SourceStore.normalize("   ") == nil)
    }
}

struct BrowseParserTests {
    @Test func parsesTagSearchResults() throws {
        let html = """
        <ol class="tag index group">
          <li><span class='canonical'>Fandom: <a class="tag" href="/tags/Harry%20Potter%20-%20J*d*%20K*d*%20Rowling">Harry Potter - J. K. Rowling</a> &lrm;(123,456)</span></li>
          <li><span>Freeform: <a class="tag" href="/tags/fluff">fluff</a> &lrm;(7)</span></li>
        </ol>
        """
        let page = try AO3Parser.tagResults(html: html, page: 1)
        #expect(page.items.count == 2)
        let first = try #require(page.items.first)
        #expect(first.name == "Harry Potter - J. K. Rowling")
        #expect(first.type == "Fandom")
        #expect(first.uses == "123,456")
        #expect(first.isCanonical)
        #expect(first.path == "/tags/Harry Potter - J*d* K*d* Rowling")
        #expect(WorkListRoute.tag(name: first.name, path: first.path).baseQuery.first?.value == "Harry Potter - J*d* K*d* Rowling")
    }

    @Test func parsesSubscriptions() throws {
        let html = """
        <dl class="subscription index group">
          <dt><a href="/works/42">A Work</a> by <a rel="author" href="/users/a/pseuds/a">a</a></dt><dd></dd>
          <dt><a href="/series/7">A Series</a> by <a rel="author" href="/users/b/pseuds/b">b</a></dt><dd></dd>
          <dt><a href="/users/c">c</a></dt><dd></dd>
        </dl>
        """
        let items = try AO3Parser.subscriptions(html: html, page: 1).items
        #expect(items.map(\.kind) == [.works, .series, .users])
        #expect(items[0].workID == 42)
        #expect(items[0].byline == "a")
    }

    @Test func parsesInboxComments() throws {
        let html = """
        <ol class="comment index group">
          <li class="unread comment group" id="feedback_comment_99">
            <h4 class="heading byline"><a href="/users/fan/pseuds/fan">fan</a> on <a href="/works/5/chapters/8?show_comments=true#comment_99">My Fic</a>
              <span class="posted datetime">2 days ago</span></h4>
            <blockquote class="userstuff"><p>Loved it!</p></blockquote>
          </li>
        </ol>
        """
        let comment = try #require(AO3Parser.inbox(html: html, page: 1).items.first)
        #expect(comment.commenter == "fan")
        #expect(comment.targetTitle == "My Fic")
        #expect(comment.workID == 5)
        #expect(comment.body == "Loved it!")
        #expect(comment.isUnread)
    }

    @Test func encodesTagFilterParameters() {
        var query = WorkSearchQuery(sortColumn: .kudos)
        query.fandomNames = "A,B"
        query.excludedTagNames = "C"
        query.rating = .general
        let items = Dictionary(query.filterItems(page: 1).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        #expect(items["work_search[sort_column]"] == "kudos_count")
        #expect(items["work_search[other_tag_names]"] == "A,B")
        #expect(items["work_search[excluded_tag_names]"] == "C")
        #expect(items["include_work_search[rating_ids][]"] == "10")
        #expect(items["page"] == nil)
    }

    @Test func encodesTagParam() {
        #expect(AO3Paths.tagParam("Mr. & Mrs./Smith?#") == "Mr*d* *a* Mrs*d**s*Smith*q**h*")
    }
}

struct AccountActionTests {
    @Test func parsesLanguageOptions() throws {
        let html = """
        <select name="work_search[language_id]" id="work_search_language_id">
          <option value=""></option><option value="en">English</option><option value="zh">中文-普通话 國語</option>
        </select>
        """
        let languages = try AO3Parser.languageOptions(html: html)
        #expect(languages.map(\.code) == ["en", "zh"])
    }

    @Test func parsesWorkActionForms() throws {
        let html = """
        <meta name="csrf-token" content="tok">
        <ul class="work navigation actions">
          <li class="mark"><form class="button_to" method="post" action="/works/9/mark_for_later">
            <input type="hidden" name="_method" value="patch"><input type="hidden" name="authenticity_token" value="tok"></form></li>
          <li class="subscribe"><form action="/users/me/subscriptions/55" method="post">
            <input type="hidden" name="_method" value="delete">
            <input type="hidden" name="subscription[subscribable_id]" value="9">
            <input type="hidden" name="subscription[subscribable_type]" value="Work"></form></li>
        </ul>
        <div id="bookmark-form"><form action="/works/9/bookmarks" method="post">
          <input type="hidden" name="authenticity_token" value="tok">
          <input type="hidden" name="bookmark[pseud_id]" value="3">
          <input type="hidden" name="bookmark[private]" value="0">
          <input type="checkbox" name="bookmark[private]" value="1">
        </form></div>
        """
        let actions = try #require(try AO3Parser.workActions(html: html))
        #expect(!actions.isMarkedForLater)
        #expect(actions.isSubscribed)
        #expect(!actions.isBookmarked)
        #expect(actions.bookmark?.value("bookmark[pseud_id]") == "3")
        #expect(actions.authenticityToken == "tok")
    }

    @Test func mapsMicrosoftChineseCodes() {
        #expect(BingTranslator.microsoftCode("zh-TW") == "zh-Hant")
        #expect(BingTranslator.microsoftCode("zh-CN") == "zh-Hans")
        #expect(BingTranslator.microsoftCode("ja") == "ja")
    }

    @Test func sortsAO3LanguagesBySpeakers() {
        let sorted = AO3Language.bySpeakers([
            .init(code: "ko", name: "한국어"), .init(code: "zz", name: "Zzz"), .init(code: "en", name: "English"),
            .init(code: "aa", name: "Aaa"), .init(code: "zh", name: "中文-普通话 國語"), .init(code: "es", name: "Español"),
        ])
        #expect(sorted.map(\.code) == ["en", "zh", "es", "ko", "aa", "zz"])
    }

    @Test func providerSourceLanguages() {
        #expect(TranslationProviderKind.googleWeb.supportsSource("haw"))
        #expect(!TranslationProviderKind.youdaoWeb.supportsSource("de"))
        #expect(!TranslationProviderKind.apple.supportsSource("zh-HK"))
        #expect(TranslationProviderKind.deepL.sourceLanguages.contains { $0.code == "no" })
        #expect(TranslationLanguage.named("yue").englishName == "Cantonese")
        #expect(TranslationLanguage.lookup("xx") == nil)
    }

    @Test func parsesUserIcon() {
        let base = URL(string: "https://archiveofourown.org")!
        let custom = #"<div class="primary header module"><div class="icon"><a href="/users/a/pseuds/a"><img class="icon" src="https://s3.amazonaws.com/otw-ao3-icons/icons/1/standard.png?1"></a></div></div>"#
        #expect(AO3Parser.userIcon(custom, baseURL: base)?.host() == "s3.amazonaws.com")
        let fallback = #"<div class="primary header module"><div class="icon"><img class="icon" src="/images/skins/iconsets/default/icon_user.png"></div></div>"#
        #expect(AO3Parser.userIcon(fallback, baseURL: base) == nil)
    }

    @Test func decodesAccountEntryOrder() {
        #expect(AccountEntry.decode("") == [.bookmarks, .markedForLater, .history, .subscriptions, .inbox])
        #expect(AccountEntry.decode("inbox,history,inbox,bogus") == [.inbox, .history, .bookmarks, .markedForLater, .subscriptions])
    }

    @Test func parsesDownloadLinksAndInfo() throws {
        let html = """
        <ul class="work navigation actions"><li class="download"><ul class="expandable secondary">
        <li><a href="/downloads/42/My%20Work.epub?updated_at=1">EPUB</a></li>
        <li><a href="/downloads/42/My%20Work.pdf?updated_at=1">PDF</a></li>
        </ul></li></ul>
        <dl class="work meta group"><dd class="rating tags"><a class="tag" href="/tags/x">Teen And Up Audiences</a></dd>
        <dd class="fandom tags"><a class="tag" href="/tags/y">Some Fandom</a></dd>
        <dd class="language">English</dd>
        <dl class="stats"><dd class="words">1,234</dd><dd class="kudos">56</dd></dl></dl>
        <div id="workskin"><h2 class="title heading">T</h2></div>
        <div id="chapters"><div class="userstuff"><p>Hello</p></div></div>
        """
        let detail = try AO3Parser.workDetail(html: html, id: 42)
        #expect(detail.downloads["epub"] == "/downloads/42/My%20Work.epub?updated_at=1")
        #expect(detail.downloads["pdf"] != nil)
        let info = try #require(detail.info)
        #expect(info.rating == "Teen And Up Audiences")
        #expect(info.fandoms == ["Some Fandom"])
        #expect(info.language == "English")
        #expect(info.words == "1,234")
    }

    @Test func detectsCloudflareChallenge() {
        let url = URL(string: "https://archiveofourown.org/")!
        let challenge = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: [:])!
        let page = Data("<html><head><title>Just a moment...</title></head><script>window._cf_chl_opt={}</script></html>".utf8)
        #expect(AO3Client.isCloudflareChallenge(challenge, data: page))
        let normal = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
        let injected = Data("<html><title>AO3</title><script src=\"/cdn-cgi/challenge-platform/scripts/jsd/main.js\"></script></html>".utf8)
        #expect(!AO3Client.isCloudflareChallenge(normal, data: injected))
    }

    @Test func mergesBookshelvesByModificationTime() {
        let old = Date(timeIntervalSince1970: 100), new = Date(timeIntervalSince1970: 200)
        func item(_ id: Int, _ title: String, _ date: Date) -> BookshelfItem {
            BookshelfItem(work: WorkSummary(id: id, title: title), addedAt: old, modifiedAt: date)
        }
        var local = BookshelfState(items: [item(1, "old title", old), item(2, "kept", old)], manualOrder: [1, 2], orderModifiedAt: old)
        local.removed = [:]
        let remote = BookshelfState(items: [item(1, "new title", new), item(3, "added", new)],
                                    removed: ["2": new], manualOrder: [3, 1], orderModifiedAt: new)
        let merged = SyncMerge.bookshelf(local, remote)
        #expect(Set(merged.items.map(\.id)) == [1, 3])
        #expect(merged.items.first { $0.id == 1 }?.work.title == "new title")
        #expect(merged.manualOrder == [3, 1])
    }

    @Test func mergesReadingLogsPerDevice() {
        var a = ReadingLog()
        a.devices["A"] = DeviceReadingLog(days: ["2026-01-01": ["1": 60]], modifiedAt: Date(timeIntervalSince1970: 10))
        var b = ReadingLog()
        b.devices["A"] = DeviceReadingLog(days: ["2026-01-01": ["1": 120]], modifiedAt: Date(timeIntervalSince1970: 20))
        b.devices["B"] = DeviceReadingLog(days: ["2026-01-01": ["1": 30]], modifiedAt: Date(timeIntervalSince1970: 5))
        let merged = a.merged(with: b)
        #expect(merged.devices["A"]?.days["2026-01-01"]?["1"] == 120)
        #expect(merged.devices["B"] != nil)
    }

    @Test func subscribeFormGetsPageTokenAndCommit() throws {
        let html = """
        <html><head><meta name="csrf-token" content="pagetok"></head><body>
        <ul class="work navigation actions"><li class="subscribe">
        <form class="ajax-create-destroy" action="/users/me/subscriptions" method="post">
        <input type="hidden" name="subscription[subscribable_id]" value="42">
        <input type="hidden" name="subscription[subscribable_type]" value="Work">
        <input type="submit" name="commit" value="Subscribe">
        </form></li></ul></body></html>
        """
        let form = try #require(try AO3Parser.subscribeForm(html: html))
        #expect(form.value("authenticity_token") == "pagetok")
        #expect(form.value("commit") == "Subscribe")
        #expect(form.value("subscription[subscribable_type]") == "Work")
    }

    @Test func sanitizesDownloadFileNames() {
        #expect(AO3Client.fileName("A/B: C?") == "A B  C")
        #expect(AO3Client.fileName("  ") == "work")
    }
}

struct OfflineTests {
    @Test func crc32MatchesKnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func zipStartsWithStoredMimetype() {
        var zip = ZipWriter()
        zip.add("mimetype", "application/epub+zip")
        zip.add("a.txt", "hello")
        let data = zip.finish()
        // 本機檔頭簽名、檔名從偏移 30 開始，內容緊接在檔名之後（不壓縮）
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(String(decoding: data[30..<38], as: UTF8.self) == "mimetype")
        #expect(String(decoding: data[38..<58], as: UTF8.self) == "application/epub+zip")
        // 中央目錄結尾記錄共 2 個項目
        let end = data.suffix(22)
        #expect(end.prefix(4) == Data([0x50, 0x4B, 0x05, 0x06]))
        #expect(end[end.startIndex + 10] == 2)
    }

    @Test func translationsIgnoreChangedParagraphs() {
        var translations = OfflineTranslations(targetLanguageCode: "zh-TW")
        let paragraph = Paragraph(id: "c0-p0", text: "Hello")
        translations.entries[paragraph.id] = .init(hash: OfflineTranslations.hash("Hello"), text: "你好")
        #expect(translations.text(for: paragraph) == "你好")
        #expect(translations.text(for: Paragraph(id: "c0-p0", text: "Hello!")) == nil)
    }

    @Test func epubEscapesMarkup() {
        #expect(BilingualEPUB.escape("a < b & \"c\"\u{1}") == "a &lt; b &amp; &quot;c&quot;")
    }
}

struct LocalLibraryTests {
    private func work(_ id: Int) -> WorkSummary { WorkSummary(id: id, title: "W\(id)") }

    @Test func mergeKeepsNewerAndRespectsRemovals() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        var a = LocalLibrary()
        a.bookmarks = [LocalBookmark(work: work(1), notes: "old", createdAt: old, modifiedAt: old)]
        a.later = [LocalWorkEntry(work: work(2), date: old, modifiedAt: old)]
        var b = LocalLibrary()
        b.bookmarks = [LocalBookmark(work: work(1), notes: "new", createdAt: old, modifiedAt: new)]
        // 另一台裝置在加入之後移除了稍後閱讀
        b.removed["l:2"] = new

        let merged = a.merged(with: b)
        #expect(merged.bookmarks.first?.notes == "new")
        #expect(merged.later.isEmpty)
        #expect(merged == b.merged(with: a))
    }
}

struct ChapterTitleTests {
    @Test func splitsNumberedChapterTitles() {
        #expect(TranslationService.splitChapterTitle("Chapter 3: History and Objectivity")! == ("Chapter 3", "History and Objectivity"))
        #expect(TranslationService.splitChapterTitle("第2章：重逢")! == ("第2章", "重逢"))
        #expect(TranslationService.splitChapterTitle("Prologue: Start") == nil)
        #expect(TranslationService.splitChapterTitle("Chapter 4") == nil)
    }
}

struct ChapterNumberTests {
    @Test func usesArabicNumerals() {
        #expect(TranslationService.arabicNumerals("第二十三章") == "第23章")
        #expect(TranslationService.arabicNumerals("第一百零五部分") == "第105部分")
        #expect(TranslationService.localChapterNumber("Chapter 24", target: .named("zh-CN")) == "第24章")
        #expect(TranslationService.localChapterNumber("Prologue", target: .named("zh-CN")) == nil)
    }
}

struct NotesPlacementTests {
    @Test func endOnlyNotesStayAtTheEnd() throws {
        let html = """
        <div id="workskin">
          <div class="preface group"><h2 class="title heading">T</h2></div>
          <div id="chapters">
            <div class="chapter" id="chapter-1">
              <div class="chapter preface group"><h3 class="title">Chapter 1</h3></div>
              <div class="userstuff module" role="article"><p>Body</p></div>
              <div class="chapter preface group">
                <div id="chapter_1_endnotes" class="end notes module"><blockquote class="userstuff"><p>Chapter end</p></blockquote></div>
              </div>
            </div>
            <div class="chapter" id="chapter-2">
              <div class="chapter preface group"><h3 class="title">Chapter 2</h3>
                <div class="notes module"><blockquote class="userstuff"><p>Chapter top</p></blockquote></div>
              </div>
              <div class="userstuff module" role="article"><p>More</p></div>
            </div>
          </div>
          <div class="afterword preface group">
            <div id="work_endnotes" class="end notes module"><blockquote class="userstuff"><p>Work end</p></blockquote></div>
          </div>
        </div>
        """
        let detail = try AO3Parser.workDetail(html: html, id: 7)
        #expect(detail.notes.isEmpty)
        #expect(detail.endNotes == "Work end")
        #expect(detail.chapters[0].notes.isEmpty)
        #expect(detail.chapters[0].endNotes == "Chapter end")
        #expect(detail.chapters[1].notes == "Chapter top")
        #expect(detail.chapters[1].endNotes.isEmpty)
    }
}

struct VisitedDateTests {
    @Test func parsesLastVisited() throws {
        let date = try #require(AO3Parser.visitedDate("Last visited: 20 Oct 2026 (Update available.) Visited 3 times"))
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 20)
    }
}
