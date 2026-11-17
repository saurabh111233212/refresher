import Foundation
import Testing
@testable import RefresherCore

struct CardParserTests {
    @Test func testParsesMultilineCardsAndDropsMetadata() {
        let text = """
        #flashcards/rl/llm

        Concept notes: [[RL for LLMs]].

        What is k3?
        ?
        $\\rho - 1 - \\log\\rho$
        Unbiased and ≥ 0.
        <!--SR:!2026-10-30,0,230-->

        ---
        Two-line
        question?
        ?
        Answer.
        """
        let cards = CardParser.parse(deck: "RL for LLMs", text: text)
        #expect(cards.map(\.question) == ["What is k3?", "Two-line\nquestion?"])
        #expect(cards[0].answer == "$\\rho - 1 - \\log\\rho$\nUnbiased and ≥ 0.")
        #expect(cards[1].answer == "Answer.")
    }

    @Test func testInlineSchedulingCommentIsStripped() {
        let cards = CardParser.parse(deck: "D", text: "Q\n?\nA <!--SR:!2026-11-01,3,250-->")
        #expect(cards.first?.answer == "A")
    }

    @Test func testBlocksWithoutSeparatorOrEmptySideAreSkipped() {
        #expect(CardParser.parse(deck: "D", text: "Just a note.\n\n?\nNo question").isEmpty)
    }

    @Test func testIDIsStableAcrossAnswerEditsAndDistinctAcrossDecks() {
        let original = CardParser.parse(deck: "A", text: "Q\n?\nold")[0]
        let edited = CardParser.parse(deck: "A", text: "Q\n?\nnew")[0]
        let otherDeck = CardParser.parse(deck: "B", text: "Q\n?\nold")[0]
        #expect(original.id == edited.id)
        #expect(original.id != otherDeck.id)
        #expect(original.id == CardParser.stableID(deck: "A", question: "Q"))
    }

    @Test func testDeckNameDropsPrefixAndExtension() {
        #expect(CardParser.deckName(fromFileName: "Cards - PyTorch.md") == "PyTorch")
    }

    @Test func testParsesEveryCardInTheRealVault() throws {
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/prep/Flashcards")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return  // vault not present on this machine
        }
        for file in files where file.pathExtension == "md" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let separators = text.components(separatedBy: .newlines).filter { $0.trimmingCharacters(in: .whitespaces) == "?" }.count
            let cards = CardParser.parse(deck: CardParser.deckName(fromFileName: file.lastPathComponent), text: text)
            #expect(cards.count == separators, Comment(rawValue: file.lastPathComponent))
            #expect(Set(cards.map(\.id)).count == cards.count, Comment(rawValue: "duplicate ids in \(file.lastPathComponent)"))
        }
    }
}

struct SchedulerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    @Test func testNewCardGrades() {
        let good = Scheduler.review(nil, grade: .good, now: now)
        #expect(good.intervalDays == 1)
        #expect(good.due == now.addingTimeInterval(day))
        let easy = Scheduler.review(nil, grade: .easy, now: now)
        #expect(easy.intervalDays == 3)
        #expect(abs(easy.ease - 2.65) < 1e-9)
        let again = Scheduler.review(nil, grade: .again, now: now)
        #expect(again.due == now.addingTimeInterval(300))
        #expect(again.lapses == 0)
        #expect(abs(again.ease - 2.3) < 1e-9)
    }

    @Test func testGoodMultipliesIntervalByEase() {
        let state = ReviewState(due: now, intervalDays: 4, ease: 2.5, reviews: 3, lapses: 0)
        let next = Scheduler.review(state, grade: .good, now: now)
        #expect(next.intervalDays == 10)
        #expect(next.due == now.addingTimeInterval(10 * day))
        #expect(next.reviews == 4)
    }

    @Test func testGoodAlwaysGrowsByAtLeastADay() {
        let state = ReviewState(due: now, intervalDays: 1, ease: 1.3, reviews: 2, lapses: 1)
        #expect(Scheduler.review(state, grade: .good, now: now).intervalDays == 2)
    }

    @Test func testLapseResetsAndFloorsEase() {
        let state = ReviewState(due: now, intervalDays: 20, ease: 1.4, reviews: 5, lapses: 0)
        let next = Scheduler.review(state, grade: .again, now: now)
        #expect(next.intervalDays == 0)
        #expect(abs(next.ease - 1.3) < 1e-9)
        #expect(next.lapses == 1)
        #expect(Scheduler.review(next, grade: .good, now: now).intervalDays == 1)
    }
}

struct SessionPlannerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func card(_ name: String) -> Card { Card(id: name, deck: "D", question: name, answer: "a") }

    @Test func testDueFirstByOverdueThenNewWithinAllowance() {
        let cards = ["a", "b", "c", "n1", "n2", "n3"].map(card)
        let states: [String: ReviewState] = [
            "a": ReviewState(due: now.addingTimeInterval(-10), intervalDays: 1, ease: 2.5, reviews: 1, lapses: 0),
            "b": ReviewState(due: now.addingTimeInterval(-1000), intervalDays: 1, ease: 2.5, reviews: 1, lapses: 0),
            "c": ReviewState(due: now.addingTimeInterval(1000), intervalDays: 1, ease: 2.5, reviews: 1, lapses: 0),
        ]
        var generator = SystemRandomNumberGenerator()
        let planned = SessionPlanner.plan(cards: cards, states: states, size: 4, newAllowance: 1, now: now, generator: &generator)
        #expect(Set(planned.map(\.id)) == ["a", "b", "n1"])
        let small = SessionPlanner.plan(cards: cards, states: states, size: 1, newAllowance: 5, now: now, generator: &generator)
        #expect(small.map(\.id) == ["b"])
        #expect(SessionPlanner.counts(cards: cards, states: states, now: now) == QueueCounts(due: 2, new: 3))
    }

    @Test func testNewCardsRotateAcrossDecksInFileOrder() {
        let cards = [("A", "a1"), ("A", "a2"), ("A", "a3"), ("B", "b1"), ("C", "c1"), ("C", "c2")].map { Card(id: $0.1, deck: $0.0, question: $0.1, answer: "x") }
        #expect(SessionPlanner.roundRobinByDeck(cards).map(\.id) == ["a1", "b1", "c1", "a2", "c2", "a3"])
        var generator = SystemRandomNumberGenerator()
        let planned = SessionPlanner.plan(cards: cards, states: [:], size: 3, newAllowance: 3, now: now, generator: &generator)
        #expect(Set(planned.map(\.id)) == ["a1", "b1", "c1"])
    }

    @Test func testNegativeAllowanceAddsNoNewCards() {
        var generator = SystemRandomNumberGenerator()
        #expect(SessionPlanner.plan(cards: [card("n")], states: [:], size: 5, newAllowance: -2, now: now, generator: &generator).isEmpty)
    }
}

struct StudyLogTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func testStreakCountsGoalDaysAndToleratesUnfinishedToday() {
        var log = StudyLog()
        for day in [13, 14, 15] { for _ in 0..<3 { log.record(at: date(day), wasNew: false, calendar: calendar) } }
        log.record(at: date(12), wasNew: true, calendar: calendar)  // below goal: ends the streak
        #expect(log.streak(endingAt: date(16), goal: 3, calendar: calendar) == 3)
        #expect(log.streak(endingAt: date(15), goal: 3, calendar: calendar) == 3)
        #expect(log.streak(endingAt: date(17), goal: 3, calendar: calendar) == 0)
        #expect(log.newCards(on: date(12), calendar: calendar) == 1)
    }

    @Test func testDayKeyUsesCalendarTimeZone() {
        #expect(StudyLog.dayKey(date(15, hour: 23), calendar: calendar) == "2026-11-15")
    }
}

struct TutorTests {
    @Test func testSystemPromptCleansNotesAndKeepsInstructionsFirst() {
        let prompt = TutorContext.systemPrompt(documents: [VaultDocument(path: "Concepts/A.md", text: "#flashcards/x\nSee [[Algorithms|algos]] and [[B]].\nQ\n?\nA <!--SR:!2026-01-01,1,250-->")])
        #expect(prompt.hasPrefix(TutorPrompt.instructions))
        #expect(prompt.hasSuffix("=== Concepts/A.md ===\nSee Algorithms and B.\nQ\n?\nA\n</notes>"))
    }

    @Test func testUserTurnCarriesFocusCard() {
        let card = Card(id: "1", deck: "PyTorch", question: "What is x?", answer: "y")
        #expect(TutorContext.userTurn(question: "help me see this", focus: card) == "Card I'm looking at (PyTorch):\nQ: What is x?\nA: y\n\nhelp me see this")
        #expect(TutorContext.userTurn(question: "hi", focus: nil) == "hi")
    }

    @Test func testRequestBodyOmitsEmptyEffort() throws {
        let messages = [ChatMessage(role: .system, content: "s"), ChatMessage(role: .user, content: "u")]
        let plain = try ChatCompletions.request(apiKey: "k", settings: TutorSettings(model: "gpt-6-astra", reasoningEffort: ""), messages: messages)
        let body = try JSONSerialization.jsonObject(with: plain.httpBody!) as! [String: Any]
        #expect(body["model"] as? String == "gpt-6-astra")
        #expect(body["stream"] as? Bool == true)
        #expect(body["reasoning_effort"] == nil)
        #expect((body["messages"] as! [[String: String]]) == [["role": "system", "content": "s"], ["role": "user", "content": "u"]])
        #expect(plain.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        let low = try ChatCompletions.request(apiKey: "k", settings: TutorSettings(model: "m", reasoningEffort: "low"), messages: messages)
        #expect((try JSONSerialization.jsonObject(with: low.httpBody!) as! [String: Any])["reasoning_effort"] as? String == "low")
    }

    @Test func testParsesStreamLines() throws {
        #expect(try ChatCompletions.parse(line: #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#) == .text("Hi"))
        #expect(try ChatCompletions.parse(line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignored)
        #expect(try ChatCompletions.parse(line: #"data: {"choices":[]}"#) == .ignored)
        #expect(try ChatCompletions.parse(line: "data: [DONE]") == .done)
        #expect(try ChatCompletions.parse(line: ": keep-alive") == .ignored)
        #expect(throws: (any Error).self) { try ChatCompletions.parse(line: "data: {not json") }
    }
}

struct ProgressBackupTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func state() -> ReviewState { ReviewState(due: now, intervalDays: 2, ease: 2.5, reviews: 2, lapses: 0) }

    @Test func testRoundTripKeepsProgressAndSummarizesOnlyStudiedCards() throws {
        let studied = Card(id: "a", deck: "PyTorch", question: "view vs reshape?", answer: "x")
        let unseen = Card(id: "b", deck: "PyTorch", question: "other", answer: "y")
        var log = StudyLog()
        log.record(at: now, wasNew: true, calendar: Calendar(identifier: .gregorian))
        let backup = ProgressBackup(exportedAt: now, states: ["a": state()], log: log, cards: [studied, unseen])
        #expect(backup.cards == ["a": ProgressBackup.CardSummary(deck: "PyTorch", question: "view vs reshape?")])
        let decoded = try ProgressBackup.decode(backup.encoded())
        #expect(decoded == backup)
        #expect(String(decoding: try backup.encoded(), as: UTF8.self).contains("\"exportedAt\" : \"2027-01-15T08:00:00Z\""))
    }

    @Test func testRestoresOnlyOntoABlankInstall() {
        var log = StudyLog()
        log.record(at: now, wasNew: false, calendar: Calendar(identifier: .gregorian))
        let backup = ProgressBackup(exportedAt: now, states: ["a": state()], log: log, cards: [])
        #expect(ProgressBackup.shouldRestore(localStates: [:], localLog: StudyLog(), backup: backup))
        #expect(!ProgressBackup.shouldRestore(localStates: ["z": state()], localLog: StudyLog(), backup: backup))
        #expect(!ProgressBackup.shouldRestore(localStates: [:], localLog: log, backup: backup))
        let empty = ProgressBackup(exportedAt: now, states: [:], log: StudyLog(), cards: [])
        #expect(!ProgressBackup.shouldRestore(localStates: [:], localLog: StudyLog(), backup: empty))
    }

    @Test func testReadsExpirationFromProvisioningProfileBlob() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-23T20:30:00Z</date><key>Name</key><string>x</string></dict></plist>
        """
        let blob = Data([0x30, 0x82, 0x01, 0x00]) + Data(plist.utf8) + Data([0xA0, 0x00, 0xFF])  // CMS wrapper bytes around the plist
        #expect(try ProvisioningProfile.expirationDate(from: blob) == ISO8601DateFormatter().date(from: "2026-11-23T20:30:00Z"))
        #expect(throws: ProvisioningProfileError.noPlist) { try ProvisioningProfile.expirationDate(from: Data([0x30, 0x82])) }
        let noDate = Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Name</key><string>x</string></dict></plist>".utf8)
        #expect(throws: ProvisioningProfileError.noExpirationDate) { try ProvisioningProfile.expirationDate(from: noDate) }
    }
}
