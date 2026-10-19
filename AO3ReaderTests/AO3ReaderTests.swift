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
