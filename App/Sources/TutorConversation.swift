import Foundation
import Observation
import RefresherCore

/// One tutor chat: what the user sees, what is sent to the model, and the streaming reply. Shared by the Tutor tab and the card.
@MainActor
@Observable
final class TutorConversation {
    let focus: Card?
    private(set) var messages: [ChatMessage] = []
    private(set) var error: String?
    private(set) var isStreaming = false

    /// The first question as sent (with the focus card attached); its bubble shows only what was typed.
    private var firstQuestionID: UUID?
    private var firstQuestionSent = ""
    private var streaming: Task<Void, Never>?

    init(focus: Card?) {
        self.focus = focus
    }

    func send(_ text: String, documents: [VaultDocument], settings: TutorSettings) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming else { return }
        guard let apiKey = Keychain.readKey() else {
            error = "No API key yet. Add it in Settings."
            return
        }
        error = nil
        let sentTurn = messages.isEmpty ? TutorContext.userTurn(question: question, focus: focus) : question
        let history = [ChatMessage(role: .system, content: TutorContext.systemPrompt(documents: documents))]
            + messages.map { ChatMessage(role: $0.role, content: $0.id == firstQuestionID ? firstQuestionSent : $0.content) }
            + [ChatMessage(role: .user, content: sentTurn)]
        let shown = ChatMessage(role: .user, content: question)
        if messages.isEmpty {
            firstQuestionID = shown.id
            firstQuestionSent = sentTurn
        }
        messages.append(shown)
        messages.append(ChatMessage(role: .assistant, content: ""))
        let reply = messages.count - 1
        isStreaming = true

        streaming = Task {
            defer { isStreaming = false }
            do {
                let request = try ChatCompletions.request(apiKey: apiKey, settings: settings, messages: history)
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as! HTTPURLResponse).statusCode
                guard status == 200 else {
                    var body = ""
                    for try await line in bytes.lines { body += line }
                    throw TutorError.http(status, body)
                }
                for try await line in bytes.lines {
                    switch try ChatCompletions.parse(line: line) {
                    case let .text(chunk): messages[reply].content += chunk
                    case .done: return
                    case .ignored: continue
                    }
                }
            } catch is CancellationError {
                // Stopped by the user; keep whatever streamed so far.
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Same, surfaced by URLSession.
            } catch {
                self.error = error.localizedDescription
                if messages[reply].content.isEmpty { messages.remove(at: reply) }
            }
        }
    }

    func stop() {
        streaming?.cancel()
    }

    func clear() {
        streaming?.cancel()
        messages = []
        firstQuestionID = nil
        error = nil
    }
}

enum TutorError: LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case let .http(status, body):
            // Only the provider's error message is shown; the request (and key) never is.
            let message = (try? JSONDecoder().decode(OpenAIError.self, from: Data(body.utf8)))?.error.message ?? String(body.prefix(200))
            return "OpenAI returned \(status): \(message)"
        }
    }

    private struct OpenAIError: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}
