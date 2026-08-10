import SwiftUI

/// Portrait poster with show name, episode title, and SnEn code.
struct ShowCardView: View {
    let episode: Episode
    var showsAirDate: Bool = false

    private var show: Show? { episode.show }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { PosterView(path: show?.posterPath) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let milestone = episode.episodeMilestone {
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
    /// When true, `logoPath` is a network wordmark rendered negated (light) and
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
        if isNetworkLogo, let url = TMDBImage.negatedNetworkLogo(logoPath) {
            ZStack {
                Color(white: 0.16)
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit().padding(size * 0.16)
                    } else {
                        textSquare
                    }
                }
            }
        } else if let url = TMDBImage.logo(logoPath, size: "w92") {
            AsyncImage(url: url) { phase in
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
                Color(white: 0.22)
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

/// Loads a TMDB poster, with a placeholder while loading / on failure.
struct PosterView: View {
    let path: String?

    var body: some View {
        AsyncImage(url: TMDBImage.poster(path)) { phase in
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
        ShowCardView(episode: PreviewSample.standardEpisode)
        ShowCardView(episode: PreviewSample.finaleEpisode, showsAirDate: true)
    }
    .frame(width: 320)
    .padding()
}
