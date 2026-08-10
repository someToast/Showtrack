import Foundation
import SwiftData

/// Seeds an in-memory context with a couple of shows for previews. Uses no
/// network and no real poster paths (previews render placeholder art).
@MainActor
enum SampleData {
    static func insert(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        let a = Show(tmdbID: 1, name: "Neon District", overview: "A neon-soaked crime drama.")
        a.providerName = "Netflix"
        context.insert(a)
        addEpisode(to: a, s: 2, e: 5, title: "Static", air: today, in: context)
        addEpisode(to: a, s: 2, e: 6, title: "Ghost Signal", air: cal.date(byAdding: .day, value: 7, to: today), in: context)

        let b = Show(tmdbID: 2, name: "The Long Orbit", overview: "Hard sci-fi aboard a generation ship.")
        b.providerName = "Apple TV+"
        context.insert(b)
        addEpisode(to: b, s: 1, e: 3, title: "Apoapsis", air: today, in: context)

        let c = Show(tmdbID: 3, name: "Copper Hollow", overview: "Small-town supernatural mystery.")
        c.providerName = "HBO"
        context.insert(c)
        addEpisode(to: c, s: 4, e: 2, title: "The Well", air: cal.date(byAdding: .day, value: 3, to: today), in: context)

        let d = Show(tmdbID: 4, name: "Cat: The Series", overview: "An expansion of the Cat cinematic universe.")
        d.providerName = "HBO"
        context.insert(d)
        addEpisode(to: d, s: 1, e: 1, title: "Found at Last", air: today, in: context)

        try? context.save()
    }

    private static func addEpisode(
        to show: Show, s: Int, e: Int, title: String, air: Date?, in context: ModelContext
    ) {
        let ep = Episode(tmdbID: Int.random(in: 1000...9_999_999),
                         seasonNumber: s, episodeNumber: e, name: title, airDate: air)
        ep.show = show
        context.insert(ep)
    }
}
