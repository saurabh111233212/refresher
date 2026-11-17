import RefresherCore
import SwiftUI

/// The free-standing Tutor tab: ask anything about the notes.
struct TutorView: View {
    @Environment(AppModel.self) private var model
    @State private var conversation = TutorConversation(focus: nil)
    @State private var draft = ""

    private static let quickAsks = ["Quiz me on something", "Explain a concept I'm likely shaky on", "Connect two ideas from my notes"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if conversation.messages.isEmpty { emptyState }
                            TutorThread(conversation: conversation)
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: conversation.messages.last?.content) {
                        if let last = conversation.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                QuickAskBar(asks: Self.quickAsks, disabled: conversation.isStreaming) { send($0) }
                TutorInput(draft: $draft, isStreaming: conversation.isStreaming, onSend: { send(draft) }, onStop: conversation.stop)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            .background(AmbientBackground())
            .navigationTitle("Tutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !conversation.messages.isEmpty {
                    Button("Clear") { conversation.clear() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask anything about your notes.").font(.headline)
            Text("All \(model.tutorDocuments.count) notes and decks are loaded as context. Answers stay short; ask for more if you want it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if Keychain.readKey() == nil {
                Text("Add your OpenAI API key in Settings first.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.top, 8)
    }

    private func send(_ text: String) {
        Haptics.tap()
        conversation.send(text, model: model)
        draft = ""
    }
}

/// The message bubbles plus any error, laid out inline (the caller supplies the scroll view).
struct TutorThread: View {
    let conversation: TutorConversation

    var body: some View {
        ForEach(conversation.messages) { message in
            bubble(message).id(message.id)
        }
        if let error = conversation.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.again)
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            Text(message.content)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if message.content.isEmpty {
            ProgressView().padding(.vertical, 6)
        } else {
            RichText(markdown: message.content, fontSize: 16)
                .padding(12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct QuickAskBar: View {
    let asks: [String]
    let disabled: Bool
    let onAsk: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(asks, id: \.self) { ask in
                    Button(ask) { onAsk(ask) }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .disabled(disabled)
    }
}

struct TutorInput: View {
    @Binding var draft: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    var fieldBackground: Color = Theme.card

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(fieldBackground.opacity(0.4)), in: RoundedRectangle(cornerRadius: 22))
                .onSubmit(onSend)
            Button {
                isStreaming ? onStop() : onSend()
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(!isStreaming && draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
