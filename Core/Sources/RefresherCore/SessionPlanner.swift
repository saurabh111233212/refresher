import Foundation

public struct QueueCounts: Equatable, Sendable {
    public let due: Int
    public let new: Int
}

public enum SessionPlanner {
    public static func counts(cards: [Card], states: [String: ReviewState], now: Date) -> QueueCounts {
        var due = 0
        var new = 0
        for card in cards {
            if let state = states[card.id] {
                if state.due <= now { due += 1 }
            } else {
                new += 1
            }
        }
        return QueueCounts(due: due, new: new)
    }

    /// Most-overdue due cards first, then unseen cards (up to `newAllowance`, rotating across decks and in file order within
    /// each), shuffled together so decks interleave.
    public static func plan<R: RandomNumberGenerator>(
        cards: [Card], states: [String: ReviewState], size: Int, newAllowance: Int, now: Date, generator: inout R
    ) -> [Card] {
        let due = cards
            .compactMap { card in states[card.id].flatMap { $0.due <= now ? (card, $0.due) : nil } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        let unseen = roundRobinByDeck(cards.filter { states[$0.id] == nil })
        var picked = Array(due.prefix(size))
        picked += unseen.prefix(min(max(newAllowance, 0), size - picked.count))
        picked.shuffle(using: &generator)
        return picked
    }

    /// One card from each deck in turn, so a short session of new cards spans subjects instead of draining the first file.
    static func roundRobinByDeck(_ cards: [Card]) -> [Card] {
        var decks: [String] = []
        var byDeck: [String: [Card]] = [:]
        for card in cards {
            if byDeck[card.deck] == nil { decks.append(card.deck) }
            byDeck[card.deck, default: []].append(card)
        }
        var result: [Card] = []
        var depth = 0
        while result.count < cards.count {
            for deck in decks where depth < byDeck[deck]!.count {
                result.append(byDeck[deck]![depth])
            }
            depth += 1
        }
        return result
    }
}

public struct StudyLog: Codable, Equatable, Sendable {
    /// Cards reviewed per calendar day, keyed "yyyy-MM-dd" in the device's time zone.
    public var reviewsByDay: [String: Int] = [:]
    public var newByDay: [String: Int] = [:]

    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public mutating func record(at date: Date, wasNew: Bool, calendar: Calendar) {
        let key = Self.dayKey(date, calendar: calendar)
        reviewsByDay[key, default: 0] += 1
        if wasNew { newByDay[key, default: 0] += 1 }
    }

    public func reviews(on date: Date, calendar: Calendar) -> Int {
        reviewsByDay[Self.dayKey(date, calendar: calendar)] ?? 0
    }

    public func newCards(on date: Date, calendar: Calendar) -> Int {
        newByDay[Self.dayKey(date, calendar: calendar)] ?? 0
    }

    /// Consecutive days with at least `goal` reviews, ending today; today not yet met doesn't break a streak running through yesterday.
    public func streak(endingAt date: Date, goal: Int, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: date)
        if reviews(on: day, calendar: calendar) < goal {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while reviews(on: day, calendar: calendar) >= goal {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
