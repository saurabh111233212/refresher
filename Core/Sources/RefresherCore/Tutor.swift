import Foundation

public struct VaultDocument: Equatable, Sendable {
    public let path: String
    public let text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case system, user, assistant }

    public var id = UUID()
    public let role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    private enum CodingKeys: String, CodingKey { case role, content }
}

public enum TutorContext {
    private static let wikilink = try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(\|[^\]]+)?\]\]"#)

    /// The system prompt: instructions followed by every document. Kept identical across calls so the provider's prompt cache hits.
    public static func systemPrompt(documents: [VaultDocument]) -> String {
        let notes = documents.map { "=== \($0.path) ===\n\(clean($0.text))" }.joined(separator: "\n\n")
        return TutorPrompt.instructions + "\n\n<notes>\n" + notes + "\n</notes>"
    }

    /// The card under discussion rides in the user turn, not the system prompt, so the cached prefix stays stable.
    public static func userTurn(question: String, focus: Card?) -> String {
        guard let focus else { return question }
        return "Card I'm looking at (\(focus.deck)):\nQ: \(focus.question)\nA: \(focus.answer)\n\n\(question)"
    }

    static func clean(_ text: String) -> String {
        let kept = text.components(separatedBy: .newlines)
            .map(CardParser.stripSchedulingComment)
            .filter { !CardParser.isTagLine($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
        let range = NSRange(kept.startIndex..., in: kept)
        return wikilink.stringByReplacingMatches(in: kept, range: range, withTemplate: "$1").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TutorSettings: Codable, Equatable, Sendable {
    public var model: String
    /// Empty means the provider default; otherwise sent as `reasoning_effort`.
    public var reasoningEffort: String

    public init(model: String, reasoningEffort: String) {
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public enum ChatCompletions {
    public static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private struct Body: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let reasoningEffort: String?

        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case reasoningEffort = "reasoning_effort"
        }
    }

    public static func request(apiKey: String, settings: TutorSettings, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        let effort = settings.reasoningEffort.isEmpty ? nil : settings.reasoningEffort
        request.httpBody = try JSONEncoder().encode(Body(model: settings.model, messages: messages, stream: true, reasoningEffort: effort))
        return request
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    public enum StreamEvent: Equatable, Sendable {
        case text(String)
        case done
        case ignored
    }

    /// One server-sent-events line of a streamed chat completion.
    public static func parse(line: String) throws -> StreamEvent {
        guard line.hasPrefix("data:") else { return .ignored }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        let chunk = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8))
        let text = chunk.choices.compactMap(\.delta.content).joined()
        return text.isEmpty ? .ignored : .text(text)
    }
}
