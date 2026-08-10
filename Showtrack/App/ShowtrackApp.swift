import SwiftUI
import SwiftData

@main
struct ShowtrackApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(Persistence.shared)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await EpisodeNotifier.refresh(context: Persistence.shared.mainContext) }
            }
        }
    }
}
