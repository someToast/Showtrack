import SwiftUI
import SwiftData
import UIKit

/// Wraps a captured photo so it can drive an `item`-based results sheet.
private struct ScannedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var shows: [Show]
    @Query(sort: [SortDescriptor(\Episode.airDate)]) private var episodes: [Episode]

    private enum AppTab: Hashable { case home, library, add, scan }

    @State private var selection: AppTab = .home
    @State private var tabBeforeScan: AppTab = .home
    @State private var addSessionID = UUID()
    @State private var showingScanCamera = false
    @State private var scanned: ScannedImage?

    var body: some View {
        TabView(selection: $selection) {
            Tab("Shows", systemImage: "tv", value: AppTab.home) {
                trackingTab
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView(embedded: true)
            }
            Tab("Add", systemImage: "plus.circle", value: AppTab.add) {
                AddShowView(embedded: true, onFinished: { selection = .home })
                    .id(addSessionID)
            }
            Tab("Scan", systemImage: "camera.viewfinder", value: AppTab.scan) {
                Color.clear
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selection) { previous, current in
            switch current {
            case .scan:
                // Scan is an action, not a destination. Let the tab finish
                // activating first (deferring the present), then open the camera
                // and remember where to return — reverting selection *during* the
                // change leaves the tab-bar highlight stuck between two tabs.
                tabBeforeScan = previous
                Task { showingScanCamera = true }
            case .add:
                // Always enter Add in its default state.
                addSessionID = UUID()
            default:
                break
            }
        }
        // Camera as a full-screen cover (separate presentation channel from the
        // results sheet, so the capture → results handoff is reliable on the
        // first scan too). Cancelling captures nothing and returns to the tab.
        .fullScreenCover(isPresented: $showingScanCamera, onDismiss: {
            // Cancelled (nothing captured) → return now. If a photo *was*
            // captured the results sheet is opening, so we return when it closes
            // instead — otherwise the tab is left blank on Scan.
            if scanned == nil { selection = tabBeforeScan }
        }) {
            CameraPicker { image in
                scanned = ScannedImage(image: image)
                // Return to the prior tab now so the results sheet sits over it,
                // not over the blank Scan tab.
                selection = tabBeforeScan
            }
            .ignoresSafeArea()
        }
        // Item-driven: presents when a photo is captured, auto-clears on dismiss.
        .sheet(item: $scanned, onDismiss: { selection = tabBeforeScan }) { captured in
            AddShowView(initialImage: captured.image)
        }
        .task {
            #if DEBUG
            // Launch with `-seedSampleData` (scheme arg) to populate the shelves
            // with fixed dates for UI work. No effect in release.
            if ProcessInfo.processInfo.arguments.contains("-seedSampleData"), shows.isEmpty {
                SampleData.insert(into: context)
            }
            #endif

            // Backfill provider/backdrop for shows added before that fetch existed.
            await MetadataBackfiller.run(context: context)
        }
    }

    private var trackingTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ShelfView(
                        title: "Today",
                        episodes: todayEpisodes,
                        emptyMessage: "Nothing airing today."
                    )
                    ShelfView(
                        title: "This Week",
                        episodes: weekEpisodes,
                        emptyMessage: "Nothing in the next 7 days.",
                        showsAirDate: true
                    )
                }
                .padding(.vertical)
            }
            .navigationTitle("Showtrack")
            .overlay {
                if shows.isEmpty {
                    ContentUnavailableView {
                        Label("No shows yet", systemImage: "tv")
                    } description: {
                        Text("Add a show to start tracking its episodes.")
                    } actions: {
                        Button("Add Show") { selection = .add }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: Bucketing

    private var trackedEpisodes: [Episode] {
        episodes.filter { $0.show?.isTracking ?? false }
    }

    private var todayEpisodes: [Episode] {
        let cal = Calendar.current
        return trackedEpisodes.filter { ep in
            guard let day = ep.localAirDay else { return false }
            return cal.isDateInToday(day)
        }
    }

    private var weekEpisodes: [Episode] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
              let weekEnd = cal.date(byAdding: .day, value: 8, to: today) else { return [] }
        return trackedEpisodes.filter { ep in
            guard let day = ep.localAirDay else { return false }
            return day >= tomorrow && day < weekEnd
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(Persistence.previewContainer())
}
