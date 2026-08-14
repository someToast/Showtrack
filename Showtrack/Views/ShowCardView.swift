import SwiftUI

/// Portrait poster for a group of same-day episodes: the lowest episode's
/// metadata, an aggregated milestone badge, and a count badge when collapsed.
struct ShowCardView: View {
    let group: EpisodeGroup
    var showsAirDate: Bool = false

    private var episode: Episode { group.representative }
    private var show: Show? { episode.show }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { PosterView(path: show?.posterPath) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let milestone = group.milestone {
                            EpisodeTypeChit(text: milestone)
                        }
                        if showsAirDate, let label = airDateLabel {
                            DateChit(text: label)
                        }
                    }
                    .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if show?.providerLogoPath != nil || show?.providerName != nil {
                        // Inset inside the poster's top-left corner.
                        ProviderBadge(
                            logoPath: show?.providerLogoPath,
                            name: show?.providerName,
                            size: 28.8,
                            isNetworkLogo: show?.providerIsNetworkLogo ?? false
                        )
                        .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if group.count > 1 {
                        CountBadge(count: group.count).padding(6)
                    }
                }

            Text(show?.name ?? "Unknown")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.top,6)

            Text(episode.name.isEmpty ? "TBA" : episode.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(episode.seasonEpisodeCode)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var airDateLabel: String? {
        guard let day = episode.localAirDay else { return nil }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return Self.chitFormatter.string(from: day)
    }

    /// Locale-aware short weekday + day, e.g. "Thu 6".
    private static let chitFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f
    }()
}

/// Small reversed (light-on-dark) rounded date badge for the poster corner.
private struct DateChit: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Count of episodes released the same day, shown lower-right of the poster.
/// The number is full-brightness white.
private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.7), in: Capsule())
    }
}

/// Premiere/finale milestone badge — same shape as `DateChit`, blue (#2d47a7).
struct EpisodeTypeChit: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Color(red: 45 / 255, green: 71 / 255, blue: 167 / 255),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}

/// Streaming provider shown as a rounded-square app-icon tile (JustWatch/TMDB
/// provider logos are uniform square tiles with their own brand backgrounds).
/// Falls back to the provider name on a dark chip if no logo is available.
struct ProviderBadge: View {
    let logoPath: String?
    let name: String?
    var size: CGFloat = 24
    /// When true, `logoPath` is a network wordmark rendered as a white template
    /// (tinted from its alpha, so it's white regardless of the logo's own colors)
    /// scaled-to-fit on a dark square, rather than an opaque provider tile.
    var isNetworkLogo: Bool = false

    var body: some View {
        tile
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
    }

    @ViewBuilder
    private var tile: some View {
        if isNetworkLogo, let url = TMDBImage.logo(logoPath, size: "w185") {
            ZStack {
                GeneratedTile.background(for: name, fallback: Color(white: 0.16))
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        // Tint to white from the logo's alpha, so every network
                        // wordmark reads white regardless of its own colors.
                        image.renderingMode(.template)
                            .resizable().scaledToFit()
                            .foregroundStyle(.white)
                            .padding(size * 0.16)
                    } else {
                        textSquare
                    }
                }
            }
        } else if let url = TMDBImage.logo(logoPath, size: "w92") {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    textSquare
                }
            }
        } else {
            textSquare
        }
    }

    /// Square text fallback — same footprint and style as a logo tile, with the
    /// provider name centered and scaled to fit.
    @ViewBuilder
    private var textSquare: some View {
        if let name {
            ZStack {
                GeneratedTile.background(for: name, fallback: Color(white: 0.22))
                Text(name)
                    .font(.system(size: size * 0.34, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.3)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(size * 0.1)
            }
        } else {
            Color.clear
        }
    }
}

/// Brand background colors for generated provider tiles — white network
/// wordmarks and text-square fallbacks — keyed by normalized network name.
/// Names not listed keep the default gray.
enum GeneratedTile {
    /// Background for a generated tile: the authored brand color if one exists
    /// for this network, otherwise `fallback`.
    @MainActor
    static func background(for name: String?, fallback: Color) -> Color {
        guard let name else { return fallback }
        return generatedTileColors[ShowImporter.normalizedProviderName(name)] ?? fallback
    }

    // Background colors for generated provider tiles (white network wordmarks and
    // text fallbacks), keyed by normalized network name. Authored with
    // tools/generated-tile-colors.html. Names not listed use the default tile color.
    static let generatedTileColors: [String: Color] = [
        "5": Color(red: 0.886, green: 0.859, blue: 0.012),   // 5 (wordmark)  #E2DB03
        "bbcfour": Color(red: 0.439, green: 0, blue: 0.898),   // BBC Four (wordmark)  #7000E5
        "bbcone": Color(red: 0.925, green: 0.314, blue: 0.29),   // BBC One (wordmark)  #EC504A
        "bbctwo": Color(red: 0.059, green: 0.667, blue: 0.553),   // BBC Two (wordmark)  #0FAA8D
        "cbs": Color(red: 0.086, green: 0.471, blue: 0.882),   // CBS (wordmark)  #1678E1
        "channel4": Color(red: 0.227, green: 0.8, blue: 0),   // Channel 4 (wordmark)  #3ACC00
        "comedycentral": Color(red: 0.855, green: 0.631, blue: 0.027),   // Comedy Central (wordmark)  #DAA107
        "e4": Color(red: 0.537, green: 0, blue: 1),   // E4 (wordmark)  #8900FF
        "epix": Color(red: 0.553, green: 0.435, blue: 0.184),   // Epix (wordmark)  #8D6F2F
        "espn": Color(red: 0.929, green: 0.11, blue: 0.141),   // ESPN (wordmark)  #ED1C24
        "espn+": Color(red: 0.933, green: 0.11, blue: 0.141),   // ESPN+ (wordmark)  #EE1C24
        "espn2": Color(red: 0.812, green: 0, blue: 0),   // ESPN2 (wordmark)  #CF0000
        "espndeportes": Color(red: 0.953, green: 0.18, blue: 0.188),   // ESPN Deportes (wordmark)  #F32E30
        "fox": Color(red: 0.859, green: 0.518, blue: 0),   // FOX (wordmark)  #DB8400
        "imdbtv": Color(red: 0.824, green: 0.122, blue: 0.294),   // IMDb TV (wordmark)  #D21F4B
        "itv1": Color(red: 0.09, green: 0.678, blue: 0.71),   // ITV1 (wordmark)  #17ADB5
        "max": Color(red: 0.071, green: 0.2, blue: 0.973),   // Max (wordmark)  #1233F8
        "nickelodeon": Color(red: 0.8, green: 0.333, blue: 0),   // Nickelodeon (wordmark)  #CC5500
        "nicktoons": Color(red: 0.267, green: 0.62, blue: 0.918),   // Nicktoons (wordmark)  #449EEA
        "paramount+withshowtime": Color(red: 1, green: 0.125, blue: 0.173),   // Paramount+ with Showtime (wordmark)  #FF202C
        "paramountnetwork": Color(red: 0.118, green: 0.392, blue: 1),   // Paramount Network (wordmark)  #1E64FF
        "showtime": Color(red: 0.961, green: 0.114, blue: 0.145),   // Showtime (wordmark)  #F51D25
        "spotify": Color(red: 0.094, green: 0.706, blue: 0.318),   // Spotify (wordmark)  #18B451
        "syfy": Color(red: 0.733, green: 0.8, blue: 0),   // Syfy (wordmark)  #BBCC00
        "univision": Color(red: 0, green: 0.6, blue: 0.349),   // Univision (wordmark)  #009959
    ]
}

/// Loads a TMDB poster, with a placeholder while loading / on failure.
struct PosterView: View {
    let path: String?

    var body: some View {
        CachedAsyncImage(url: TMDBImage.poster(path)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty where path != nil:
                ZStack {
                    Rectangle().fill(.quaternary)
                    ProgressView()
                }
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "tv")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    HStack(alignment: .top, spacing: 16) {
        ShowCardView(group: EpisodeGroup(episodes: [PreviewSample.standardEpisode]))
        ShowCardView(group: EpisodeGroup(episodes: PreviewSample.episodes), showsAirDate: true)
    }
    .frame(width: 320)
    .padding()
}
