import Foundation
import Observation
import RefresherCore

struct StudySettings: Codable, Equatable {
    var sessionSize = 10
    var dailyGoal = 20
    var newPerDay = 15
    var excludedDecks: Set<String> = []
    var tutor = TutorSettings(model: "gpt-6-astra", reasoningEffort: "low")
}

@MainActor
@Observable
final class AppModel {
    private(set) var cards: [Card] = []
    private(set) var tutorDocuments: [VaultDocument] = []
    private(set) var states: [String: ReviewState] = [:]
    private(set) var log = StudyLog()
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var vaultName: String?
    private(set) var backupError: String?
    private(set) var lastBackup: Date?
    private(set) var activityError: String?
    /// Events not yet appended to the vault log; kept on disk so an offline or failed write catches up later.
    private(set) var pendingActivity: [String]
    private var isFlushingActivity = false
    var settings: StudySettings { didSet { Storage.save(settings, as: .settings) } }

    private let calendar = Calendar.current

    init() {
        settings = Storage.load(StudySettings.self, from: .settings) ?? StudySettings()
        states = Storage.load([String: ReviewState].self, from: .states) ?? [:]
        log = Storage.load(StudyLog.self, from: .log) ?? StudyLog()
        pendingActivity = Storage.load([String].self, from: .pendingActivity) ?? []
        vaultName = VaultAccess.savedFolderName()
    }

    var decks: [String] { Array(Set(cards.map(\.deck))).sorted() }
    var activeCards: [Card] { cards.filter { !settings.excludedDecks.contains($0.deck) } }
    var counts: QueueCounts { SessionPlanner.counts(cards: activeCards, states: states, now: .now) }
    var reviewedToday: Int { log.reviews(on: .now, calendar: calendar) }
    var streak: Int { log.streak(endingAt: .now, goal: settings.dailyGoal, calendar: calendar) }
    var hasVault: Bool { vaultName != nil }

    /// When this install stops launching. Free Apple ID signing lasts 7 days; simulator builds have no profile.
    let installExpiry: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
        do {
            return try ProvisioningProfile.expirationDate(from: Data(contentsOf: url))
        } catch {
            fatalError("Unreadable embedded.mobileprovision: \(error)")
        }
    }()

    func reload() async {
        guard hasVault else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await VaultAccess.loadSavedFolder()
            cards = snapshot.cards
            tutorDocuments = snapshot.tutorDocuments
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            return
        }
        await restoreFromBackupIfBlank()
    }

    /// On a fresh install (or after the app was deleted), pick progress back up from the vault copy.
    private func restoreFromBackupIfBlank() async {
        guard states.isEmpty, log.reviewsByDay.isEmpty else { return }
        do {
            guard let data = try await VaultAccess.readBackup() else { return }
            let backup = try ProgressBackup.decode(data)
            guard ProgressBackup.shouldRestore(localStates: states, localLog: log, backup: backup) else { return }
            states = backup.states
            log = backup.log
            Storage.save(states, as: .states)
            Storage.save(log, as: .log)
            lastBackup = backup.exportedAt
        } catch {
            backupError = "Couldn't read the progress backup: \(error.localizedDescription)"
        }
    }

    /// Copies progress into the vault. Called when a session ends and when the app goes to the background.
    func backUpProgress() async {
        guard hasVault else { return }
        let backup = ProgressBackup(exportedAt: .now, states: states, log: log, cards: cards)
        do {
            try await VaultAccess.writeBackup(backup.encoded())
            lastBackup = backup.exportedAt
            backupError = nil
        } catch {
            backupError = "Couldn't back up progress to the vault: \(error.localizedDescription)"
        }
    }

    func useVault(at url: URL) async {
        do {
            try VaultAccess.saveFolder(url)
            vaultName = url.lastPathComponent
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func show(_ error: Error) {
        loadError = error.localizedDescription
    }

    func planSession(size: Int) -> [Card] {
        let allowance = settings.newPerDay - log.newCards(on: .now, calendar: calendar)
        var generator = SystemRandomNumberGenerator()
        return SessionPlanner.plan(cards: activeCards, states: states, size: size, newAllowance: allowance, now: .now, generator: &generator)
    }

    /// Extra unseen cards beyond today's new-card allowance, for when the queue is empty and there's still time to kill.
    func planBonusSession(size: Int) -> [Card] {
        var generator = SystemRandomNumberGenerator()
        return SessionPlanner.plan(cards: activeCards, states: states, size: size, newAllowance: size, now: .now, generator: &generator)
    }

    func record(_ card: Card, grade: Grade) {
        let wasNew = states[card.id] == nil
        states[card.id] = Scheduler.review(states[card.id], grade: grade, now: .now)
        log.record(at: .now, wasNew: wasNew, calendar: calendar)
        Storage.save(states, as: .states)
        Storage.save(log, as: .log)
        logActivity(ReviewEvent(at: .now, card: CardReference(card), grade: grade, state: states[card.id]!))
    }

    func logActivity(_ event: some Encodable) {
        do {
            pendingActivity.append(try ActivityLog.line(event))
        } catch {
            fatalError("Could not encode activity event: \(error)")
        }
        Storage.save(pendingActivity, as: .pendingActivity)
        Task { await flushActivity() }
    }

    /// Appends queued events to the vault log, oldest first; only what was written is dropped from the queue.
    func flushActivity() async {
        guard hasVault, !isFlushingActivity else { return }
        isFlushingActivity = true
        defer { isFlushingActivity = false }
        // Loops to pick up events logged while a write was in flight.
        while !pendingActivity.isEmpty {
            let batch = pendingActivity
            do {
                try await VaultAccess.appendActivity(batch.joined())
            } catch {
                activityError = "Couldn't write the activity log to the vault: \(error.localizedDescription)"
                return
            }
            pendingActivity.removeFirst(batch.count)
            Storage.save(pendingActivity, as: .pendingActivity)
            activityError = nil
        }
    }

    func resetProgress() {
        states = [:]
        log = StudyLog()
        Storage.save(states, as: .states)
        Storage.save(log, as: .log)
        // Overwrite the vault copy too, or the next launch would restore what was just erased.
        Task { await backUpProgress() }
    }

    func toggleDeck(_ deck: String) {
        if settings.excludedDecks.contains(deck) {
            settings.excludedDecks.remove(deck)
        } else {
            settings.excludedDecks.insert(deck)
        }
    }
}

/// JSON files in Application Support: on-device only, never written into the vault.
enum Storage {
    enum File: String {
        case settings, states, log, pendingActivity
    }

    private static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, from file: File) -> T? {
        let url = directory.appendingPathComponent("\(file.rawValue).json")
        guard let data = try? Data(contentsOf: url) else { return nil }  // first launch
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            fatalError("Corrupt \(file.rawValue).json: \(error)")
        }
    }

    static func save<T: Encodable>(_ value: T, as file: File) {
        let url = directory.appendingPathComponent("\(file.rawValue).json")
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            fatalError("Could not save \(file.rawValue).json: \(error)")
        }
    }
}
