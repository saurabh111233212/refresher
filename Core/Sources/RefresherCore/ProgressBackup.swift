import Foundation

/// A copy of review progress kept in the vault: insurance if the app is deleted, and readable on the laptop (deck + question per card).
public struct ProgressBackup: Codable, Equatable, Sendable {
    public struct CardSummary: Codable, Equatable, Sendable {
        public let deck: String
        public let question: String
    }

    /// A dot-file so Obsidian doesn't list or index it.
    public static let fileName = ".refresher-progress.json"

    public var version = 1
    public var exportedAt: Date
    public var states: [String: ReviewState]
    public var log: StudyLog
    /// Only cards that have progress; cards no longer in the vault keep their last-known summary out of the file.
    public var cards: [String: CardSummary]

    public init(exportedAt: Date, states: [String: ReviewState], log: StudyLog, cards: [Card]) {
        self.exportedAt = exportedAt
        self.states = states
        self.log = log
        self.cards = Dictionary(uniqueKeysWithValues: cards.filter { states[$0.id] != nil }.map { ($0.id, CardSummary(deck: $0.deck, question: $0.question)) })
    }

    public var isEmpty: Bool { states.isEmpty && log.reviewsByDay.isEmpty }

    /// Restore only onto a blank install, so the backup never overwrites progress made on the device.
    public static func shouldRestore(localStates: [String: ReviewState], localLog: StudyLog, backup: ProgressBackup) -> Bool {
        localStates.isEmpty && localLog.reviewsByDay.isEmpty && !backup.isEmpty
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ProgressBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProgressBackup.self, from: data)
    }
}

public enum ProvisioningProfileError: Error, Equatable {
    case noPlist
    case noExpirationDate
}

public enum ProvisioningProfile {
    /// `embedded.mobileprovision` is a signed CMS blob wrapping an XML plist; the plist carries `ExpirationDate`.
    public static func expirationDate(from data: Data) throws -> Date {
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            throw ProvisioningProfileError.noPlist
        }
        let plist = try PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil)
        guard let date = (plist as? [String: Any])?["ExpirationDate"] as? Date else { throw ProvisioningProfileError.noExpirationDate }
        return date
    }
}
