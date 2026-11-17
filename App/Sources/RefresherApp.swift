import SwiftUI

@main
struct RefresherApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.reload() }
                .onChange(of: scenePhase) { _, phase in
                    // Pick up vault edits made in Obsidian or on the Mac while the app was in the background.
                    if phase == .active { Task { await model.reload() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Review", systemImage: "bolt.fill") }
            TutorView()
                .tabItem { Label("Tutor", systemImage: "sparkles") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}
