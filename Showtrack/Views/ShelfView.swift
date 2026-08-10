import SwiftUI

/// A titled, horizontally-scrolling row of show cards.
struct ShelfView: View {
    let title: String
    let episodes: [Episode]
    let emptyMessage: String
    var showsAirDate: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                if !episodes.isEmpty {
                    CountPill(count: episodes.count)
                }
            }

            if episodes.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(episodes) { episode in
                        NavigationLink {
                            EpisodeDetailView(episode: episode)
                        } label: {
                            ShowCardView(episode: episode, showsAirDate: showsAirDate)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

/// Rounded count pill shown flush-right in a shelf header and Library rows.
struct CountPill: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(.secondarySystemFill), in: Capsule())
    }
}
