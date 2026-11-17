import RefresherCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var session: [Card]?
    @State private var showingFolderPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !model.hasVault {
                        welcome
                    } else {
                        if let error = model.loadError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.again)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        progressHeader
                        startButtons
                        queueSummary
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(AmbientBackground())
            // An invisible renderer warms WebKit so the first card in a session shows instantly.
            .background { RichText(markdown: "").frame(width: 1, height: 1).opacity(0).allowsHitTesting(false) }
            .navigationTitle("Refresher")
            .refreshable { await model.reload() }
            .fullScreenCover(item: Binding(get: { session.map(SessionBox.init) }, set: { session = $0?.cards })) { box in
                SessionView(cards: box.cards)
            }
            .folderPicker(isPresented: $showingFolderPicker)
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("Point me at your vault")
                .font(.title2.bold())
            Text("In Files, open iCloud Drive › Obsidian and pick the vault folder, the one with Flashcards and Concepts inside. Cards stay in sync with Obsidian; review progress stays on this phone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose folder") { showingFolderPicker = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 60)
    }

    private var progressHeader: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(1, Double(model.reviewedToday) / Double(max(model.settings.dailyGoal, 1))))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: model.reviewedToday)
                VStack(spacing: 0) {
                    Text("\(model.reviewedToday)").font(.title.bold()).contentTransition(.numericText())
                    Text("of \(model.settings.dailyGoal)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(model.streak > 0 ? Theme.accent : .secondary)
                    Text("\(model.streak)-day streak").font(.headline)
                }
                Text(model.reviewedToday >= model.settings.dailyGoal ? "Goal done. Anything more is bonus." : "\(model.settings.dailyGoal - model.reviewedToday) to keep the streak going.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
    }

    private var startButtons: some View {
        let counts = model.counts
        let queueEmpty = model.planSession(size: 1).isEmpty
        return VStack(spacing: 12) {
            Button {
                Haptics.tap()
                let planned = queueEmpty ? model.planBonusSession(size: model.settings.sessionSize) : model.planSession(size: model.settings.sessionSize)
                if !planned.isEmpty { session = planned }
            } label: {
                VStack(spacing: 4) {
                    Text(queueEmpty ? (counts.new > 0 ? "Bonus round" : "All caught up") : "Quick \(min(model.settings.sessionSize, counts.due + counts.new))")
                        .font(.title2.bold())
                    Text(queueEmpty ? (counts.new > 0 ? "A few extra new cards" : "Come back later") : "about \(max(1, model.settings.sessionSize / 4)) min")
                        .font(.subheadline)
                        .opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 28))
            .tint(Theme.accent)
            .disabled(queueEmpty && counts.new == 0)

            GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach([3, 5, 20], id: \.self) { size in
                    Button {
                        Haptics.tap()
                        let planned = model.planSession(size: size)
                        session = planned.isEmpty ? model.planBonusSession(size: size) : planned
                    } label: {
                        Text(size == 3 ? "Just 3" : "\(size) cards")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(counts.new == 0 && queueEmpty)
                }
            }
            }
        }
    }

    private var queueSummary: some View {
        let counts = model.counts
        return HStack {
            stat(value: counts.due, label: "due", color: Theme.accent)
            Divider().frame(height: 36)
            stat(value: counts.new, label: "unseen", color: Theme.easy)
            Divider().frame(height: 36)
            stat(value: model.activeCards.count, label: "cards", color: .secondary)
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            if model.isLoading { ProgressView().padding(8) }
        }
    }

    private func stat(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SessionBox: Identifiable {
    let cards: [Card]
    var id: String { cards.map(\.id).joined() }
}

extension View {
    func folderPicker(isPresented: Binding<Bool>) -> some View {
        modifier(FolderPicker(isPresented: isPresented))
    }
}

private struct FolderPicker: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
            switch result {
            case let .success(url): Task { await model.useVault(at: url) }
            case let .failure(error): model.show(error)
            }
        }
    }
}
