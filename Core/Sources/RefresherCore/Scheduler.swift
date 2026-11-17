import Foundation

public enum Grade: String, Codable, Sendable, CaseIterable {
    case again, good, easy
}

public struct ReviewState: Codable, Equatable, Sendable {
    public var due: Date
    public var intervalDays: Double
    public var ease: Double
    public var reviews: Int
    public var lapses: Int

    public init(due: Date, intervalDays: Double, ease: Double, reviews: Int, lapses: Int) {
        self.due = due
        self.intervalDays = intervalDays
        self.ease = ease
        self.reviews = reviews
        self.lapses = lapses
    }
}

/// SM-2 style scheduling with three grades, sized for quick phone sessions.
public enum Scheduler {
    public static let startingEase = 2.5
    public static let minimumEase = 1.3
    /// A missed card comes back within the same sitting rather than tomorrow.
    public static let relearnDelay: TimeInterval = 5 * 60
    private static let day: TimeInterval = 24 * 60 * 60

    public static func review(_ state: ReviewState?, grade: Grade, now: Date) -> ReviewState {
        let previous = state ?? ReviewState(due: now, intervalDays: 0, ease: startingEase, reviews: 0, lapses: 0)
        var next = previous
        next.reviews += 1
        switch grade {
        case .again:
            next.intervalDays = 0
            next.ease = max(minimumEase, previous.ease - 0.2)
            next.lapses += previous.reviews > 0 ? 1 : 0
            next.due = now.addingTimeInterval(relearnDelay)
            return next
        case .good:
            next.intervalDays = previous.intervalDays == 0 ? 1 : max(previous.intervalDays + 1, previous.intervalDays * previous.ease)
        case .easy:
            next.ease = previous.ease + 0.15
            next.intervalDays = previous.intervalDays == 0 ? 3 : previous.intervalDays * previous.ease * 1.3
        }
        next.due = now.addingTimeInterval(next.intervalDays * day)
        return next
    }
}
