import RefresherCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingFolderPicker = false
    @State private var keyDraft = ""
    @State private var hasKey = Keychain.readKey() != nil
    @State private var confirmingReset = false

    private static let efforts = ["", "low", "medium", "high"]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Vault") {
                    LabeledContent("Folder", value: model.vaultName ?? "Not chosen")
                    Button(model.hasVault ? "Choose a different folder" : "Choose folder") { showingFolderPicker = true }
                    if model.hasVault {
                        Button("Reload cards") { Task { await model.reload() } }
                        LabeledContent("Cards loaded", value: "\(model.cards.count)")
                    }
                }

                Section("Sessions") {
                    Stepper("Quick session: \(model.settings.sessionSize) cards", value: $model.settings.sessionSize, in: 3...40)
                    Stepper("Daily goal: \(model.settings.dailyGoal) reviews", value: $model.settings.dailyGoal, in: 5...200, step: 5)
                    Stepper("New cards per day: \(model.settings.newPerDay)", value: $model.settings.newPerDay, in: 0...100, step: 5)
                }

                if !model.decks.isEmpty {
                    Section("Decks") {
                        ForEach(model.decks, id: \.self) { deck in
                            Toggle(isOn: Binding(get: { !model.settings.excludedDecks.contains(deck) }, set: { _ in model.toggleDeck(deck) })) {
                                HStack {
                                    Circle().fill(Theme.deckColor(deck)).frame(width: 10, height: 10)
                                    Text(deck)
                                    Spacer()
                                    Text("\(model.cards.filter { $0.deck == deck }.count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    if hasKey {
                        LabeledContent("API key", value: "Saved on this device")
                        Button("Remove key", role: .destructive) {
                            Keychain.deleteKey()
                            hasKey = false
                        }
                    } else {
                        SecureField("Paste OpenAI API key", text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save key") {
                            Keychain.saveKey(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                            keyDraft = ""
                            hasKey = true
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    TextField("Model", text: $model.settings.tutor.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Reasoning effort", selection: $model.settings.tutor.reasoningEffort) {
                        ForEach(Self.efforts, id: \.self) { effort in
                            Text(effort.isEmpty ? "Default" : effort.capitalized).tag(effort)
                        }
                    }
                } header: {
                    Text("Tutor")
                } footer: {
                    Text("Each question sends your notes and decks (except Reported Questions) as context, about 25k tokens, most of it cached after the first call.")
                }

                Section {
                    if confirmingReset {
                        Button("Yes, erase all review history", role: .destructive) {
                            model.resetProgress()
                            confirmingReset = false
                        }
                        Button("Cancel") { confirmingReset = false }
                    } else {
                        Button("Reset review progress", role: .destructive) { confirmingReset = true }
                    }
                }
            }
            .navigationTitle("Settings")
            .folderPicker(isPresented: $showingFolderPicker)
        }
    }
}
