import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// Tries a CloudKit-backed store first (the shipping configuration — requires
/// an Apple Developer team and the iCloud entitlement). If that can't be set up
/// — e.g. running in a simulator with no iCloud account, or before signing is
/// configured — it falls back to a local-only store so the app still runs.
@MainActor
enum Persistence {
    static let shared: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Show.self, Episode.self])

        do {
            let cloud = ModelConfiguration("Showtrack", schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: cloud)
        } catch {
            #if DEBUG
            print("[Persistence] CloudKit container unavailable, falling back to local store: \(error)")
            #endif
        }

        do {
            let local = ModelConfiguration("Showtrack-local", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Unable to create any ModelContainer: \(error)")
        }
    }

    /// In-memory container for SwiftUI previews and tests.
    @MainActor
    static func previewContainer(seeded: Bool = true) -> ModelContainer {
        let schema = Schema([Show.self, Episode.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        if seeded {
            SampleData.insert(into: container.mainContext)
        }
        return container
    }
}
