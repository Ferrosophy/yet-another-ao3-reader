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
