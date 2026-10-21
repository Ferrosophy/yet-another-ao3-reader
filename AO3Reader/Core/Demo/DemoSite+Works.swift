import Foundation

/// 展示模式的示範作品：全部為 AI 生成的原創短篇，作者、原作、角色與評論者都是虛構的。
extension DemoSite {
    struct StoryChapter: Sendable {
        var title: String
        /// 段落；"***" 為分隔線
        var paragraphs: [String]
    }

    struct StoryComment: Sendable {
        var author: String
        var guest = false
        /// 多章作品的評論所屬章節（從 1 開始）
        var chapter: Int? = nil
        var date: String
        var text: String
        var depth = 0
    }

    struct Spec: Sendable {
        var id: Int
        var title: String
        var author: String
        var summary: String
        var notes = ""
        var endNotes = ""
        var rating: String
        var categories: [String]
        var fandoms: [String]
        var relationships: [String] = []
        var characters: [String] = []
        var freeforms: [String]
        var kudos: String
        var hits: String
        var updated: String
        /// 預計總章數；nil 表示已完結
        var plannedChapters: Int? = nil
        var chapters: [StoryChapter]
        var comments: [StoryComment] = []
    }

    static let works: [Work] = [moonbridge, smallHours, teaService, lighthouse, fieldGuide, goodnight].map(make)

    private static func make(_ spec: Spec) -> Work {
        let chapters = spec.chapters.enumerated().map { index, chapter in
            DemoChapterBuilder.chapter(index: index, title: chapter.title, paragraphs: chapter.paragraphs)
        }
        let words = spec.chapters.flatMap(\.paragraphs).joined(separator: " ").split(whereSeparator: \.isWhitespace).count
        let total = spec.plannedChapters.map(String.init) ?? String(chapters.count)
        let info = WorkSummary(
            id: spec.id, title: spec.title, authors: [spec.author], fandoms: spec.fandoms, rating: spec.rating,
            warnings: ["No Archive Warnings Apply"], categories: spec.categories, relationships: spec.relationships,
            characters: spec.characters, freeforms: spec.freeforms, summary: spec.summary, language: "English",
            words: words.formatted(), chapters: "\(chapters.count)/\(total)", kudos: spec.kudos, hits: spec.hits,
            updated: spec.updated
        )
        func group(_ localized: String, _ english: String, _ kind: String, _ names: [String]) -> WorkTagGroup? {
            guard !names.isEmpty else { return nil }
            let tags = names.map { WorkTag(name: $0, path: "/tags/\(AO3Paths.tagParam($0))/works") }
            return WorkTagGroup(title: AO3Term.label(localized, english), tags: tags, isFandom: kind == "fandom", kind: kind)
        }
        let groups: [WorkTagGroup?] = [
            group(String(localized: "分級"), "Rating", "rating", [spec.rating]),
            group(String(localized: "警告"), "Archive Warnings", "warning", info.warnings),
            group(String(localized: "分類"), "Category", "category", spec.categories),
            group(String(localized: "原作"), "Fandoms", "fandom", spec.fandoms),
            group(String(localized: "配對"), "Relationships", "relationship", spec.relationships),
            group(String(localized: "角色"), "Characters", "character", spec.characters),
            group(String(localized: "其他標籤"), "Additional Tags", "freeform", spec.freeforms),
        ]
        let detail = WorkDetail(
            id: spec.id, title: spec.title, authors: [spec.author], summary: spec.summary, chapters: chapters,
            notes: spec.notes, endNotes: spec.endNotes, tagGroups: groups.compactMap { $0 },
            authorLinks: [WorkTag(name: spec.author, path: "/users/\(spec.author)/pseuds/\(spec.author)")],
            info: info
        )
        let comments = spec.comments.enumerated().map { index, comment in
            WorkComment(
                id: "demo-\(spec.id)-\(index)",
                author: comment.author,
                isGuest: comment.guest,
                posted: comment.chapter.map { "on Chapter \($0) · \(comment.date)" } ?? comment.date,
                text: comment.text,
                depth: comment.depth
            )
        }
        return Work(detail: detail, comments: comments)
    }

    // MARK: - Stories

    private static let moonbridge = Spec(
        id: 9_100_001,
        title: "The Last Train to Moonbridge",
        author: "tidepool_sonata",
        summary: "Wren Alder is certain she is lost, which is exactly the kind of passenger the midnight train to Moonbridge is looking for.",
        notes: "Written for a cozy-fantasy prompt night. Thank you for reading, and please mind the gap on Thursdays!",
        rating: "General Audiences",
        categories: ["Gen"],
        fandoms: ["Moonbridge Academy"],
        characters: ["Wren Alder", "The Conductor", "Felix Inkwell"],
        freeforms: ["Fluff", "Found Family", "Magical Trains", "Cozy Fantasy"],
        kudos: "1,284",
        hits: "9,731",
        updated: "18 Oct 2026",
        chapters: [StoryChapter(title: "Chapter 1", paragraphs: [
            "The last train to Moonbridge leaves at a quarter past midnight, and it only stops for people who are certain they are lost.",
            "Wren Alder had been certain for three days. She stood on the empty platform with a suitcase full of borrowed sweaters, listening to the rails hum a tune she almost recognised.",
            "“You’re early,” said the conductor, a tall woman whose coat was stitched together from old timetables. “Nobody is ever early. Either you’re very brave or very confused.”",
            "“Both,” Wren admitted.",
            "The conductor laughed, a sound like a small station bell, and held out a ticket that had not existed a moment ago. It read, in handwriting that kept rearranging itself: ADMIT ONE LOST THING. RETURN WHEN FOUND.",
            "“What if I never find it?”",
            "“Then you’ll have a very long and very interesting journey,” said the conductor. “Mind the gap. It bites on Thursdays.”",
            "The train arrived without a whistle, all brass and lamplight, its windows full of strangers who looked up and smiled as if they had been waiting for her. A boy with ink on his cuffs shuffled over to make room. A grey cat in a surprisingly tidy scarf studied her from the seat opposite with grave approval.",
            "“First time?” asked the boy.",
            "“Is it that obvious?”",
            "“You’re holding your ticket like it might fly away.” He grinned. “It might, actually. Keep it in your pocket and don’t read it twice.”",
            "Wren tucked the ticket away. Outside, the dark slid by in long silver ribbons, and somewhere beyond the glass a bridge made of moonlight began to unfold, plank by plank, just wide enough for one small train.",
            "For the first time in three days, she wasn’t afraid. She was simply, wonderfully on her way.",
        ])],
        comments: [
            StoryComment(author: "pomelo_and_pine", date: "Sun 18 Oct 2026 09:12PM UTC",
                    text: "This is exactly the cozy, slightly strange magic I needed tonight. The conductor in her timetable coat is going to live in my head forever."),
            StoryComment(author: "tidepool_sonata", date: "Sun 18 Oct 2026 10:03PM UTC",
                    text: "Thank you so much! I had far too much fun deciding what the cat’s scarf looked like.", depth: 1),
            StoryComment(author: "Wandering Reader", guest: true, date: "Mon 19 Oct 2026 07:45AM UTC",
                    text: "“Mind the gap, it bites on Thursdays” — I’m stealing that line for my group chat."),
            StoryComment(author: "lanternfish_89", date: "Mon 19 Oct 2026 02:30PM UTC",
                    text: "Please tell me there’s more Moonbridge coming. I need to know what Wren’s lost thing is!"),
            StoryComment(author: "tidepool_sonata", date: "Mon 19 Oct 2026 03:18PM UTC",
                    text: "There will be! A sequel is brewing, I promise.", depth: 1),
        ]
    )

    private static let smallHours = Spec(
        id: 9_100_002,
        title: "Inventory of Small Hours",
        author: "A_Verdigris",
        summary: "At 3:40 a.m. the only list Odalys can finish is the bakery inventory. Teo has other ideas about what needs counting.",
        rating: "Teen And Up Audiences",
        categories: ["Gen"],
        fandoms: ["Original Work"],
        relationships: ["Odalys Marsh & Teo Brandt"],
        characters: ["Odalys Marsh", "Teo Brandt"],
        freeforms: ["Slice of Life", "Insomnia", "Bakery", "Hurt/Comfort", "Friendship"],
        kudos: "862",
        hits: "5,410",
        updated: "16 Oct 2026",
        chapters: [StoryChapter(title: "Chapter 1", paragraphs: [
            "At 3:40 a.m. the bakery smells like warm butter and unfinished sentences.",
            "Odalys counts the flour sacks twice, because the first count never feels honest. Eleven. Eleven again. The ovens tick as they cool, and the window over the sink has gone the soft blue of a bruise that is finally healing.",
            "“You don’t have to do inventory tonight,” says Teo from the doorway, hair flattened on one side, a blanket draped over his shoulders like a cape that has given up.",
            "“I know.”",
            "“Then why—”",
            "“Because it’s the only list I can finish.”",
            "Teo doesn’t answer. He crosses the floor in mismatched socks and takes the clipboard from her hands, gently, the way you might lift a sleeping bird from a branch. He reads the page aloud: flour, sugar, yeast, and a mystery line that just says the good butter.",
            "“That’s not a real category,” Odalys says.",
            "“It is now.” He writes a new line beneath it in his terrible handwriting: Odalys, rested (low). Then, after a moment: Teo, here (plenty).",
            "She laughs, finally — a short, surprised sound that rings off the steel counters.",
            "They don’t fix anything that night. They share the heel of yesterday’s rye with far too much jam, and they watch the window turn from blue to grey to the pale gold of a day that hasn’t made up its mind yet.",
            "It is the smallest inventory either of them has ever taken. It is also, Odalys thinks, the first one that comes out right.",
        ])],
        comments: [
            StoryComment(author: "quiet_orchard", date: "Fri 16 Oct 2026 11:20PM UTC",
                    text: "“Odalys, rested (low). Teo, here (plenty).” I’m not crying, you’re crying. Such gentle, beautiful writing."),
            StoryComment(author: "marmalade_moth", date: "Sat 17 Oct 2026 01:05AM UTC",
                    text: "The line about the only list she can finish hit very close to home. Thank you for writing this."),
            StoryComment(author: "A_Verdigris", date: "Sat 17 Oct 2026 09:40AM UTC",
                    text: "That means a lot, thank you. Take care of yourself!", depth: 1),
        ]
    )

    private static let teaService = Spec(
        id: 9_100_003,
        title: "Tea Service at the End of the World",
        author: "oat_milk_astronaut",
        summary: "When the universe announces it will end on a Tuesday, the crew of the Orbital Tea House insists on finishing afternoon service first.",
        notes: "Updates every other weekend. Pip is my favourite and I will not be taking questions.",
        rating: "Teen And Up Audiences",
        categories: ["Gen"],
        fandoms: ["Orbital Tea House"],
        characters: ["Captain Ilse Varga", "Pip the Tea Drone", "The Critic"],
        freeforms: ["Humor", "Space Opera", "Found Family", "Tea", "End of the World"],
        kudos: "2,047",
        hits: "15,882",
        updated: "20 Oct 2026",
        plannedChapters: 5,
        chapters: [
            StoryChapter(title: "Chapter 1: The Kettle Warning", paragraphs: [
                "The first sign that the universe was ending was a polite notification on the kettle.",
                "“Attention,” it chirped. “Reality will cease in approximately forty minutes. Would you like to descale before then?”",
                "Captain Ilse Varga lowered her teacup very slowly. “Pip, how many guests are booked for afternoon service?”",
                "The tea drone hovered into view, its single lens glowing an anxious amber. “Seventeen, Captain. Three vegetarians, one nebula, and a very important critic.”",
                "“Then we have forty minutes,” said Ilse, rolling up her sleeves, “to make the best scones in the history of everything.”",
            ]),
            StoryChapter(title: "Chapter 2: The Critic", paragraphs: [
                "The critic arrived by wormhole, which was in poor taste, and shook out a coat that rained very small stars across the carpet.",
                "“I have reviewed every tearoom between here and the edge of time,” she announced. “Most of them serve disappointment with a doily.”",
                "Pip offered a plate. The critic took a scone, examined it like a jeweller, and bit into it with the focus of someone defusing a bomb.",
                "Nobody breathed. Even the nebula held very still.",
                "“Hm,” said the critic. Then, which was worse: “Hm.” Then she reached for a second scone.",
            ]),
            StoryChapter(title: "Chapter 3: Last Orders", paragraphs: [
                "With nine minutes to spare, the crew set out the good china.",
                "The universe did not end all at once. It simply grew quiet, the way a room does when everyone leans in to hear the same thing, and the stars outside the window began to switch off one by one, like the lights of a house at bedtime.",
                "“Another cup, Captain?” asked Pip.",
                "Ilse smiled and held out her saucer. “Always,” she said. “We have time.”",
            ]),
        ],
        comments: [
            StoryComment(author: "Tea Enthusiast", guest: true, chapter: 1, date: "Sat 10 Oct 2026 06:22PM UTC",
                    text: "The kettle asking whether you’d like to descale before the end of reality is perfect. Subscribed!"),
            StoryComment(author: "bookbinder_june", chapter: 2, date: "Sun 18 Oct 2026 12:47PM UTC",
                    text: "The critic’s second scone is the most dramatic moment I’ve read all week. 10/10, would end the universe for scones."),
            StoryComment(author: "stardust_and_static", chapter: 3, date: "Tue 20 Oct 2026 08:15PM UTC",
                    text: "The stars switching off like house lights at bedtime… that image is going to stay with me for a long time."),
            StoryComment(author: "oat_milk_astronaut", chapter: 3, date: "Tue 20 Oct 2026 09:02PM UTC",
                    text: "Thank you! Two more chapters to go, and Pip has Plans.", depth: 1),
        ]
    )

    private static let lighthouse = Spec(
        id: 9_100_004,
        title: "Letters from the Lighthouse Keeper",
        author: "paper_lantern_club",
        summary: "A year of letters between a lighthouse keeper who talks to her lamp and a mainland friend who is saving her the best chair.",
        endNotes: "I love epistolary stories so much. If you have a favourite, please tell me about it in the comments!",
        rating: "General Audiences",
        categories: ["F/F"],
        fandoms: ["The Lamplighter's Atlas"],
        relationships: ["Maren Voss/Isolde Crane"],
        characters: ["Maren Voss", "Isolde Crane"],
        freeforms: ["Epistolary", "Letters", "Lighthouses", "Pining", "Hopeful Ending"],
        kudos: "1,563",
        hits: "8,904",
        updated: "12 Oct 2026",
        chapters: [StoryChapter(title: "Chapter 1", paragraphs: [
            "Dear Isolde,",
            "The sea has been restless all week, so the lamp has been working double shifts. I leave it a cup of tea on the railing every evening. I know that’s absurd. In my defence, it has never once complained.",
            "You asked whether the island is lonely. Honestly? Only in the way a good book is lonely, which is to say: full of voices that don’t need me to answer.",
            "***",
            "Dear Maren,",
            "Your letter arrived soaked, and I could only read every third word, so I have decided it said something wonderful. The postman tells me the supply boat nearly turned back in the swell. Please do not die of heroism before spring. I am saving you the best chair.",
            "***",
            "Dear Isolde,",
            "I counted the ships tonight. Forty-one passed the point, and every one of them saw the light and went home safe, and not one of them knew my name. I find I don’t mind. There is a particular kind of happiness in being the reason someone else’s evening ends well.",
            "Come in April. The sea is gentler then, and the puffins have opinions.",
            "Yours, under a very bright sky,\nMaren",
        ])],
        comments: [
            StoryComment(author: "sea_glass_notes", date: "Mon 12 Oct 2026 04:51PM UTC",
                    text: "Epistolary stories done well are my weakness, and this one is done so well. The tea for the lamp!!"),
            StoryComment(author: "ferrywoman", date: "Tue 13 Oct 2026 08:09AM UTC",
                    text: "“Please do not die of heroism before spring.” I am framing that and hanging it in my kitchen."),
        ]
    )

    private static let fieldGuide = Spec(
        id: 9_100_005,
        title: "A Field Guide to Things I Am Keeping Anyway",
        author: "Quillfeather_Moss",
        summary: "Isolde keeps a notebook of things that are not hers to keep. Maren finds page three.",
        rating: "General Audiences",
        categories: ["F/F"],
        fandoms: ["The Lamplighter's Atlas"],
        relationships: ["Maren Voss/Isolde Crane"],
        characters: ["Maren Voss", "Isolde Crane"],
        freeforms: ["Fluff", "Established Relationship", "Drabble", "Notebooks"],
        kudos: "734",
        hits: "3,215",
        updated: "8 Oct 2026",
        chapters: [StoryChapter(title: "Chapter 1", paragraphs: [
            "Isolde keeps a notebook labelled Things That Are Not Mine To Keep. It includes the view from the east window, the good pen, and the way the mornings feel in April.",
            "“You’ve listed me,” Maren observes, reading over her shoulder.",
            "“Page three.”",
            "“Under which heading?”",
            "Isolde turns the page and shows her. The old heading has been crossed out. Beneath it, in careful letters, someone has written a new one: Things I Am Going To Try Keeping Anyway.",
            "Maren doesn’t say anything. She just takes the pen — the good pen — and adds her own name underneath, and then, after a moment’s thought, draws a very small lighthouse beside it.",
        ])],
        comments: [
            StoryComment(author: "mossy_windowsill", date: "Thu 8 Oct 2026 10:30PM UTC",
                    text: "The very small lighthouse. I have to lie down."),
        ]
    )

    private static let goodnight = Spec(
        id: 9_100_006,
        title: "Seven Ways to Say Goodnight to a Robot",
        author: "midnight_cartographer",
        summary: "A girl, a household robot that does not need to sleep, and seven attempts at the perfect goodnight.",
        rating: "General Audiences",
        categories: ["Gen"],
        fandoms: ["Original Work"],
        characters: ["Junie", "Unit Seven"],
        freeforms: ["Robots", "Bedtime Stories", "Fluff", "Short & Sweet"],
        kudos: "1,019",
        hits: "4,876",
        updated: "2 Oct 2026",
        chapters: [StoryChapter(title: "Chapter 1", paragraphs: [
            "One. “Goodnight,” said Junie, because it was the first word she had learned to say at bedtime.",
            "Two. “Sleep well,” she said, because someone had once said it to her.",
            "Three. “See you in the morning,” she said, which was a promise.",
            "Four. “Don’t let the bugs bite,” she said, and Unit Seven searched its manuals for a bug-bite protocol and found none.",
            "Five. “I’ll leave the light on,” she said, and she did, and the robot — which did not sleep, which had never needed to — kept watch beside it until dawn.",
            "Six. “Goodnight, Unit Seven,” she said, and for the first time it answered: “Goodnight, Junie.”",
            "Seven. She said nothing at all. She simply leaned against its warm metal shoulder, and that was the best goodnight yet.",
        ])],
        comments: [
            StoryComment(author: "Robot Fan", guest: true, date: "Fri 2 Oct 2026 07:14PM UTC",
                    text: "Number six made me gasp out loud. What a lovely little story."),
            StoryComment(author: "compass_rose", date: "Sat 3 Oct 2026 11:58AM UTC",
                    text: "Reading this to my kid tonight. Thank you for something so warm."),
        ]
    )
}

/// 把示範章節的段落轉成閱讀器使用的 `Chapter`（段落 ID 與 AO3 解析結果相同的格式）
private enum DemoChapterBuilder {
    static func chapter(index: Int, title: String, paragraphs: [String]) -> Chapter {
        let items = paragraphs.enumerated().map { number, text in
            text == "***"
                ? Paragraph(id: "c\(index)-p\(number)", text: "", kind: .separator)
                : Paragraph(id: "c\(index)-p\(number)", text: text, kind: .body)
        }
        return Chapter(id: index, title: title, paragraphs: items)
    }
}
