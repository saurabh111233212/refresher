import RefresherCore
import SwiftUI

/// The tutor under a revealed answer: three one-tap asks, a free-form box, and the replies inline on the card.
struct CardTutor: View {
    @Environment(AppModel.self) private var model
    let conversation: TutorConversation
    @State private var draft = ""

    /// Short labels fit one row on a phone card; the full question is what gets sent.
    private static let asks: [(label: String, question: String, icon: String)] = [
        ("See it", "Help me see this. Give me the intuition behind the question and the answer.", "eye"),
        ("Example", "Give me a tiny concrete example or numeric check that makes this click.", "number"),
        ("Why care", "Why does this matter in practice for training LLMs with RL?", "lightbulb"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("Tutor").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Self.asks, id: \.label) { ask in
                    Button {
                        send(ask.question)
                    } label: {
                        Label(ask.label, systemImage: ask.icon)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .glassEffect(.regular.tint(Theme.accent.opacity(0.18)).interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
            }
            .disabled(conversation.isStreaming)

            TutorThread(conversation: conversation)

            TutorInput(draft: $draft, isStreaming: conversation.isStreaming, onSend: { send(draft) }, onStop: conversation.stop, fieldBackground: Theme.background)
        }
    }

    private func send(_ text: String) {
        Haptics.tap()
        conversation.send(text, documents: model.tutorDocuments, settings: model.settings.tutor)
        draft = ""
    }
}
