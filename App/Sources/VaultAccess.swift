import Foundation
import RefresherCore

struct VaultSnapshot: Sendable {
    let cards: [Card]
    let tutorDocuments: [VaultDocument]
}

enum VaultError: LocalizedError {
    case noFolder
    case notAVault(String)

    var errorDescription: String? {
        switch self {
        case .noFolder: "Pick your vault folder in Settings."
        case let .notAVault(name): "“\(name)” has no Flashcards folder. Pick the vault folder itself (the one containing Flashcards and Concepts)."
        }
    }
}

/// Reads the Obsidian vault in place through a security-scoped bookmark, so edits on the Mac show up without a rebuild.
enum VaultAccess {
    private static let bookmarkKey = "vaultBookmark"
    private static let nameKey = "vaultName"
    /// Kept out of the tutor's context: the same set the desktop tutor bundle leaves out.
    static let excludedFromTutor: Set<String> = ["Flashcards/Cards - Reported Questions.md"]

    static func savedFolderName() -> String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    static func saveFolder(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
    }

    static func loadSavedFolder() async throws -> VaultSnapshot {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { throw VaultError.noFolder }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { try saveFolder(url) }
        return try await Task.detached(priority: .userInitiated) { try read(vault: url) }.value
    }

    private static func read(vault: URL) throws -> VaultSnapshot {
        let accessing = vault.startAccessingSecurityScopedResource()
        defer { if accessing { vault.stopAccessingSecurityScopedResource() } }

        let flashcards = try markdownFiles(in: vault.appendingPathComponent("Flashcards"), vaultName: vault.lastPathComponent)
        let conceptsFolder = vault.appendingPathComponent("Concepts")
        let concepts = FileManager.default.fileExists(atPath: conceptsFolder.path) ? try markdownFiles(in: conceptsFolder, vaultName: vault.lastPathComponent) : []
        let karpathy = vault.appendingPathComponent("Karpathy.md")
        let extras = FileManager.default.fileExists(atPath: karpathy.path) ? [karpathy] : []

        var cards: [Card] = []
        var documents: [VaultDocument] = []
        for file in extras + concepts + flashcards {
            let text = try coordinatedRead(file)
            let relative = file.path.replacingOccurrences(of: vault.path + "/", with: "")
            if flashcards.contains(file) {
                cards += CardParser.parse(deck: CardParser.deckName(fromFileName: file.lastPathComponent), text: text)
            }
            if !excludedFromTutor.contains(relative) {
                documents.append(VaultDocument(path: relative, text: text))
            }
        }
        return VaultSnapshot(cards: cards, tutorDocuments: documents)
    }

    /// Lists `.md` files, including ones iCloud hasn't downloaded yet (shown as `.Name.md.icloud` placeholders).
    private static func markdownFiles(in folder: URL, vaultName: String) throws -> [URL] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch CocoaError.fileReadNoSuchFile {
            throw VaultError.notAVault(vaultName)
        }
        return names.compactMap { name -> URL? in
            if name.hasSuffix(".md") { return folder.appendingPathComponent(name) }
            if name.hasPrefix("."), name.hasSuffix(".md.icloud") {
                return folder.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
            }
            return nil
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A coordinated read makes iCloud download a placeholder before handing the file over.
    private static func coordinatedRead(_ url: URL) throws -> String {
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try String(contentsOf: readURL, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
