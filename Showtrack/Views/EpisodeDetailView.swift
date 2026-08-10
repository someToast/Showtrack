import SwiftUI
import SwiftData

/// Content detail for a tapped episode: large image up top (episode still when
/// available, otherwise the show's backdrop/poster), then show name, episode
/// title, SnEn, provider, and synopsis.
struct EpisodeDetailView: View {
    let episode: Episode

    private var show: Show? { episode.show }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topImage

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let show {
                            Text(show.name).font(.title2.bold())
                        }
                        
                        HStack(spacing: 8) {
                            Text(episode.seasonEpisodeCode)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let day = episode.localAirDay {
                                Text(day, format: .dateTime.weekday(.abbreviated).month().day())
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !episode.name.isEmpty {
                        Text(episode.name)
                            .font(.title3.bold())
                            .padding(.top, 12)
                    }

                    if !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    if show?.providerName != nil {
                        Text("Streaming data by JustWatch")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(show?.name ?? "Episode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var synopsis: String {
        episode.overview.isEmpty ? (show?.overview ?? "") : episode.overview
    }

    /// Episode still first, then show backdrop, then poster.
    private var topImageURL: URL? {
        TMDBImage.still(episode.stillPath, size: "w780")
            ?? TMDBImage.backdrop(show?.backdropPath, size: "w780")
            ?? TMDBImage.poster(show?.posterPath, size: "w780")
    }

    private var topImage: some View {
        AsyncImage(url: topImageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty where topImageURL != nil:
                ZStack { Rectangle().fill(.quaternary); ProgressView() }
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "tv").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if show?.providerLogoPath != nil || show?.providerName != nil {
                // Lower-left of the header image, 200% of the base badge size.
                ProviderBadge(
                    logoPath: show?.providerLogoPath,
                    name: show?.providerName,
                    size: 48,
                    isNetworkLogo: show?.providerIsNetworkLogo ?? false
                )
                .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let milestone = episode.episodeMilestone {
                EpisodeTypeChit(text: milestone).padding(12)
            }
        }
    }
}

/// Series detail: series artwork + description, then the dates of all known
/// upcoming episodes.
struct ShowDetailView: View {
    let show: Show

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topImage

                VStack(alignment: .leading, spacing: 10) {
                    Text(show.name).font(.title2.bold())

                    if !show.overview.isEmpty {
                        Text(show.overview).font(.body)
                    }

                    upcomingSection

                    if show.providerName != nil {
                        Text("Streaming data by JustWatch")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var upcomingSection: some View {
        Text("Upcoming")
            .font(.title2.bold())
            .padding(.top, 16)

        if upcoming.isEmpty {
            Text("No upcoming episodes scheduled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(upcoming) { episode in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let day = episode.localAirDay {
                                Text(Self.dateLabel(for: day))
                                    .font(.headline.weight(.medium))
                            }
                            Text(subtitle(for: episode))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let milestone = episode.episodeMilestone {
                            EpisodeTypeChit(text: milestone)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var upcoming: [Episode] { show.upcomingEpisodes }

    private func subtitle(for episode: Episode) -> String {
        episode.name.isEmpty
            ? episode.seasonEpisodeCode
            : "\(episode.seasonEpisodeCode) · \(episode.name)"
    }

    /// "Thursday, August 13" — year appended only when beyond the current year.
    private static func dateLabel(for date: Date) -> String {
        let cal = Calendar.current
        let beyondThisYear = cal.component(.year, from: date) > cal.component(.year, from: .now)
        let formatter = DateFormatter()
        formatter.dateFormat = beyondThisYear ? "EEEE, MMMM d, yyyy" : "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private var topImageURL: URL? {
        TMDBImage.backdrop(show.backdropPath, size: "w780")
            ?? TMDBImage.poster(show.posterPath, size: "w780")
    }

    private var topImage: some View {
        AsyncImage(url: topImageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty where topImageURL != nil:
                ZStack { Rectangle().fill(.quaternary); ProgressView() }
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "tv").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if show.providerLogoPath != nil || show.providerName != nil {
                ProviderBadge(
                    logoPath: show.providerLogoPath,
                    name: show.providerName,
                    size: 48,
                    isNetworkLogo: show.providerIsNetworkLogo
                )
                .padding(12)
            }
        }
    }
}

/// Sample data for previews, backed by a retained in-memory container so the
/// model objects stay valid. Exposed as plain values so `#Preview` bodies can be
/// bare view expressions — nothing type-erased (like a `PreviewModifier`) or
/// wrapping (like `.modelContainer`) in front of the previewed view, so Xcode's
/// canvas "Selectable" mode can drill into it.
enum PreviewSample {
    @MainActor static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Show.self, Episode.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        let show = Show(
            tmdbID: 1,
            name: "Neon District",
            overview: "A burnt-out detective works the rain-slicked underbelly of a city that never sleeps, chasing a case that keeps rewriting itself."
        )
        show.providerName = "Netflix"
        context.insert(show)

        let seed: [(Int, Int, String, String, Int, String?)] = [
            (2, 5, "Static", "", 0, nil),
            (2, 6, "Ghost Signal", "", 7, nil),
            (2, 7, "Blackout", "", 14, nil),
            (2, 8, "Last Call",
             "The case closes the only way it can — an old debt comes due under the neon.",
             21, "finale"),
        ]
        for (s, e, title, overview, days, type) in seed {
            let episode = Episode(
                tmdbID: s * 100 + e, seasonNumber: s, episodeNumber: e,
                name: title, overview: overview,
                airDate: cal.date(byAdding: .day, value: days, to: today)
            )
            episode.episodeType = type
            episode.show = show
            context.insert(episode)
        }
        return container
    }()

    @MainActor static var show: Show {
        (try? container.mainContext.fetch(FetchDescriptor<Show>()))?.first
            ?? Show(tmdbID: 0, name: "Sample")
    }

    @MainActor static var standardEpisode: Episode { show.upcomingEpisodes.first ?? finaleEpisode }

    @MainActor static var finaleEpisode: Episode {
        show.upcomingEpisodes.first { $0.episodeType == "finale" }
            ?? show.upcomingEpisodes.last
            ?? Episode(tmdbID: 0, seasonNumber: 1, episodeNumber: 1)
    }
}

#Preview("Episode detail (from Shows)") {
    NavigationStack {
        EpisodeDetailView(episode: PreviewSample.finaleEpisode)
    }
}

#Preview("Show detail (from Library)") {
    NavigationStack {
        ShowDetailView(show: PreviewSample.show)
    }
}
