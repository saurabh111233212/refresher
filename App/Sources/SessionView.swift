import RefresherCore
import SwiftUI

struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Card]
    @State private var position = 0
    @State private var revealed = false
    @State private var drag: CGSize = .zero
    @State private var results: [Grade: Int] = [:]
    @State private var retried: Set<String> = []
    @State private var entering = false
    /// A fresh tutor thread per card, so the card on screen is always the one in context.
    @State private var conversation: TutorConversation

    private let total: Int

    init(cards: [Card]) {
        _queue = State(initialValue: cards)
        _conversation = State(initialValue: TutorConversation(focus: cards.first))
        total = cards.count
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if position < queue.count {
                Spacer(minLength: 8)
                cardStack
                Spacer(minLength: 8)
                controls
            } else {
                SessionSummary(results: results, onMore: startMore, onDone: { dismiss() })
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(AmbientBackground())
        .onDisappear { Task { await model.backUpProgress() } }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            HStack(spacing: 10) {
                ProgressView(value: Double(min(position, total)), total: Double(max(total, 1)))
                    .tint(Theme.accent)
                    .animation(.spring, value: position)
                Text("\(min(position, total))/\(total)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.vertical, 8)
    }

    private var cardStack: some View {
        let card = queue[position]
        return ZStack {
            if position + 1 < queue.count {
                // The next card waits behind as clear glass.
                Color.clear
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 28))
                    .scaleEffect(0.94)
                    .offset(y: 16)
            }
            // One long-lived face per session: its web view re-renders in place instead of reloading per card.
            CardFace(card: card, revealed: revealed, conversation: conversation)
                .scaleEffect(entering ? 0.94 : 1)
                .opacity(entering ? 0 : 1)
                .offset(drag)
                .rotationEffect(.degrees(Double(drag.width) / 22))
                .overlay(alignment: .top) { swipeHint }
                .gesture(swipe)
                .onTapGesture {
                    guard !revealed else { return }
                    Haptics.flip()
                    withAnimation(.spring(duration: 0.35)) { revealed = true }
                }
        }
    }

    @ViewBuilder
    private var swipeHint: some View {
        if let grade = pendingGrade {
            Text(label(for: grade))
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(color(for: grade)), in: Capsule())
                .padding(.top, 14)
        }
    }

    private var controls: some View {
        Group {
            if revealed {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        gradeButton(.again, systemImage: "arrow.uturn.left")
                        gradeButton(.good, systemImage: "checkmark")
                        gradeButton(.easy, systemImage: "bolt")
                    }
                }
            } else {
                Button {
                    Haptics.flip()
                    withAnimation(.spring(duration: 0.35)) { revealed = true }
                } label: {
                    Text("Show answer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private func gradeButton(_ grade: Grade, systemImage: String) -> some View {
        Button { commit(grade) } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3.weight(.bold))
                Text(label(for: grade)).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .tint(color(for: grade))
    }

    private var swipe: some Gesture {
        DragGesture()
            .onChanged { value in
                guard revealed else { return }
                drag = value.translation
            }
            .onEnded { _ in
                guard revealed, let grade = pendingGrade else {
                    withAnimation(.spring) { drag = .zero }
                    return
                }
                commit(grade)
            }
    }

    /// Right = good, left = again, up = easy, once the card is dragged past a threshold.
    private var pendingGrade: Grade? {
        if drag.height < -110, abs(drag.width) < 90 { return .easy }
        if drag.width > 100 { return .good }
        if drag.width < -100 { return .again }
        return nil
    }

    private func commit(_ grade: Grade) {
        let card = queue[position]
        Haptics.grade(grade != .again)
        results[grade, default: 0] += 1
        model.record(card, grade: grade)
        // A missed card comes back once at the end of this session, then waits for its schedule.
        if grade == .again, !retried.contains(card.id) {
            retried.insert(card.id)
            queue.append(card)
        }
        let exit: CGSize = switch grade {
        case .again: CGSize(width: -600, height: drag.height)
        case .good: CGSize(width: 600, height: drag.height)
        case .easy: CGSize(width: drag.width, height: -900)
        }
        withAnimation(.easeIn(duration: 0.18)) { drag = exit }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            entering = true
            drag = .zero
            revealed = false
            conversation.stop()
            position += 1
            if position < queue.count { conversation = TutorConversation(focus: queue[position]) }
            withAnimation(.spring(duration: 0.3)) { entering = false }
            if position >= queue.count { Haptics.celebrate() }
        }
    }

    private func startMore() {
        let more = model.planSession(size: 5)
        let next = more.isEmpty ? model.planBonusSession(size: 5) : more
        guard !next.isEmpty else { return dismiss() }
        queue += next
        results = [:]
        conversation = TutorConversation(focus: queue[position])
    }

    private func label(for grade: Grade) -> String {
        switch grade {
        case .again: "Again"
        case .good: "Got it"
        case .easy: "Easy"
        }
    }

    private func color(for grade: Grade) -> Color {
        switch grade {
        case .again: Theme.again
        case .good: Theme.good
        case .easy: Theme.easy
        }
    }
}

private struct CardFace: View {
    let card: Card
    let revealed: Bool
    let conversation: TutorConversation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.deck.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.deckColor(card.deck))
                .padding(.bottom, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        RichText(card: card.question, answer: card.answer, deckHex: Theme.deckHex(card.deck), revealed: revealed)
                        if revealed {
                            CardTutor(conversation: conversation)
                                .transition(.opacity)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation.messages.last?.content) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            if !revealed {
                Text("Tap to reveal")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 28).fill(Theme.card).shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct SessionSummary: View {
    @Environment(AppModel.self) private var model
    let results: [Grade: Int]
    let onMore: () -> Void
    let onDone: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(model.reviewedToday >= model.settings.dailyGoal ? "🔥" : "✨")
                .font(.system(size: 72))
                .scaleEffect(appeared ? 1 : 0.3)
                .rotationEffect(.degrees(appeared ? 0 : -30))
            Text(model.reviewedToday >= model.settings.dailyGoal ? "\(model.streak)-day streak" : "Nice. \(model.settings.dailyGoal - model.reviewedToday) more today for the streak.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                tally(results[.again] ?? 0, "again", Theme.again)
                tally(results[.good] ?? 0, "got it", Theme.good)
                tally(results[.easy] ?? 0, "easy", Theme.easy)
            }
            Spacer()
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    Button(action: onMore) {
                        Text("5 more").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.accent)
                    Button(action: onDone) {
                        Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { appeared = true } }
    }

    private func tally(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
