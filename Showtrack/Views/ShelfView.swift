import SwiftUI

/// A titled, horizontally-scrolling row of show cards.
struct ShelfView: View {
    let title: String
    let groups: [EpisodeGroup]
    let emptyMessage: String
    var showsAirDate: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    /// Raw episode count (collapsed posters still count every episode).
    private var episodeCount: Int { groups.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                if !groups.isEmpty {
                    CountPill(count: episodeCount)
                }
            }

            if groups.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        NavigationLink {
                            EpisodeDetailView(episodes: group.episodes)
                        } label: {
                            ShowCardView(group: group, showsAirDate: showsAirDate)
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
