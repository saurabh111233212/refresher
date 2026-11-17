import Foundation

public struct Card: Identifiable, Hashable, Sendable {
    /// Stable across answer edits: derived from the deck name and the question text only.
    public let id: String
    public let deck: String
    public let question: String
    public let answer: String
}

/// Parses Obsidian Spaced Repetition multi-line cards: a block of lines with a lone `?` line between question and answer.
/// Blocks are separated by blank lines; `<!--SR:...-->` scheduling comments, tag lines and `---` rules are dropped.
public enum CardParser {
    private static let schedulingComment = try! NSRegularExpression(pattern: #"<!--SR:[^>]*-->"#)

    public static func deckName(fromFileName fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        if name.hasPrefix("Cards - ") { name.removeFirst("Cards - ".count) }
        return name
    }

    public static func parse(deck: String, text: String) -> [Card] {
        var cards: [Card] = []
        var block: [String] = []

        func flush() {
            defer { block.removeAll() }
            guard let separator = block.firstIndex(of: "?") else { return }
            let question = block[..<separator].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = block[(separator + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if question.isEmpty || answer.isEmpty { return }
            cards.append(Card(id: stableID(deck: deck, question: question), deck: deck, question: question, answer: answer))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripSchedulingComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "---" {
                flush()
            } else if isTagLine(line) {
                continue
            } else {
                block.append(line)
            }
        }
        flush()
        return cards
    }

    static func stripSchedulingComment(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        return schedulingComment.stringByReplacingMatches(in: line, range: range, withTemplate: "")
    }

    static func isTagLine(_ line: String) -> Bool {
        line.hasPrefix("#") && !line.hasPrefix("# ") && !line.contains(" ")
    }

    /// FNV-1a 64-bit: deterministic across launches, unlike Swift's seeded `Hasher`.
    static func stableID(deck: String, question: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(deck)\u{1F}\(question)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
