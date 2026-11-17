import Foundation

/// The card a logged event was about; deck + question keep the log readable on the laptop after card text changes.
public struct CardReference: Codable, Equatable, Sendable {
    public let id: String
    public let deck: String
    public let question: String

    public init(_ card: Card) {
        id = card.id
        deck = card.deck
        question = card.question
    }
}

public enum TutorOutcome: String, Codable, Sendable {
    case completed, stopped, failed
}

/// One question to the tutor and its reply.
public struct TutorExchange: Codable, Equatable, Sendable {
    public var kind = "tutor"
    public let at: Date
    /// Groups the turns of one conversation (one card, or one Tutor-tab thread until Clear).
    public let conversation: UUID
    public let turn: Int
    /// nil for the Tutor tab.
    public let card: CardReference?
    public let ask: String
    public let reply: String
    public let outcome: TutorOutcome
    public let error: String?
    public let model: String

    public init(at: Date, conversation: UUID, turn: Int, card: CardReference?, ask: String, reply: String, outcome: TutorOutcome, error: String?, model: String) {
        self.at = at
        self.conversation = conversation
        self.turn = turn
        self.card = card
        self.ask = ask
        self.reply = reply
        self.outcome = outcome
        self.error = error
        self.model = model
    }
}

/// One grade given to a card, with the schedule it produced.
public struct ReviewEvent: Codable, Equatable, Sendable {
    public var kind = "review"
    public let at: Date
    public let card: CardReference
    public let grade: Grade
    public let reviews: Int
    public let lapses: Int
    public let intervalDays: Double

    public init(at: Date, card: CardReference, grade: Grade, state: ReviewState) {
        self.at = at
        self.card = card
        self.grade = grade
        reviews = state.reviews
        lapses = state.lapses
        intervalDays = state.intervalDays
    }
}

/// Append-only JSON Lines in the vault: every tutor exchange and every grade, for finding weak spots from the laptop.
public enum ActivityLog {
    /// A dot-file so Obsidian doesn't list or index it.
    public static let fileName = ".refresher-activity.jsonl"

    /// One compact JSON object plus a newline; newlines inside replies are escaped, so each event stays on one line.
    public static func line(_ event: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(event), as: UTF8.self) + "\n"
    }
}
