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
    /// Identifies this thread in the activity log; Clear starts a new one.
    private var id = UUID()
    private var turn = 0

    init(focus: Card?) {
        self.focus = focus
    }

    /// Every finished, stopped or failed exchange is logged, so weak spots can be found later.
    func send(_ text: String, model: AppModel) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming else { return }
        guard let apiKey = Keychain.readKey() else {
            error = "No API key yet. Add it in Settings."
            return
        }
        error = nil
        let settings = model.settings.tutor
        let sentTurn = messages.isEmpty ? TutorContext.userTurn(question: question, focus: focus) : question
        let history = [ChatMessage(role: .system, content: TutorContext.systemPrompt(documents: model.tutorDocuments))]
            + messages.map { ChatMessage(role: $0.role, content: $0.id == firstQuestionID ? firstQuestionSent : $0.content) }
            + [ChatMessage(role: .user, content: sentTurn)]
        let shown = ChatMessage(role: .user, content: question)
        if messages.isEmpty {
            firstQuestionID = shown.id
            firstQuestionSent = sentTurn
        }
        messages.append(shown)
        let placeholder = ChatMessage(role: .assistant, content: "")
        messages.append(placeholder)
        turn += 1
        let thisTurn = turn
        let conversationID = id
        isStreaming = true

        streaming = Task {
            defer { isStreaming = false }
            var reply = ""
            var outcome = TutorOutcome.completed
            var failure: String?
            do {
                let request = try ChatCompletions.request(apiKey: apiKey, settings: settings, messages: history)
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as! HTTPURLResponse).statusCode
                guard status == 200 else {
                    var body = ""
                    for try await line in bytes.lines { body += line }
                    throw TutorError.http(status, body)
                }
                stream: for try await line in bytes.lines {
                    switch try ChatCompletions.parse(line: line) {
                    case let .text(chunk):
                        reply += chunk
                        // Looked up by id: Clear may have emptied the thread mid-stream.
                        if let index = messages.firstIndex(where: { $0.id == placeholder.id }) { messages[index].content += chunk }
                    case .done: break stream
                    case .ignored: continue
                    }
                }
            } catch is CancellationError {
                outcome = .stopped  // keep whatever streamed so far
            } catch let urlError as URLError where urlError.code == .cancelled {
                outcome = .stopped  // same, surfaced by URLSession
            } catch {
                outcome = .failed
                failure = error.localizedDescription
                self.error = failure
                if reply.isEmpty { messages.removeAll { $0.id == placeholder.id } }
            }
            model.logActivity(TutorExchange(at: .now, conversation: conversationID, turn: thisTurn, card: focus.map(CardReference.init), ask: question, reply: reply, outcome: outcome, error: failure, model: settings.model))
        }
    }

    func stop() {
        streaming?.cancel()
    }

    func clear() {
        streaming?.cancel()
        messages = []
        firstQuestionID = nil
        id = UUID()
        turn = 0
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
