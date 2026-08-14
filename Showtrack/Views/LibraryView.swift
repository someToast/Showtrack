import SwiftUI
import SwiftData
import UIKit

/// Alphabetical list of every saved show, grouped into per-letter sections with
/// a draggable A–Z index scrubber (only letters that have shows). Swipe left to
/// delete a show (its episodes cascade, and notifications are rescheduled).
struct LibraryView: View {
    /// When shown as a tab (vs. a sheet), no Done button is needed.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Show.name) private var shows: [Show]

    var body: some View {
        NavigationStack {
            Group {
                if shows.isEmpty {
                    ContentUnavailableView {
                        Label("No shows", systemImage: "rectangle.stack")
                    } description: {
                        Text("Shows you add appear here.")
                    }
                } else {
                    sectionedList
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var sectionedList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sections, id: \.letter) { section in
                    Section {
                        ForEach(section.shows) { show in
                            NavigationLink {
                                ShowDetailView(show: show)
                            } label: {
                                row(show)
                            }
                            .listRowSeparator(
                                show === section.shows.last ? .hidden : .visible,
                                edges: .bottom
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(show)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(section.letter)
                    }
                    .id(section.letter)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .overlay(alignment: .trailing) {
                AlphaIndex(letters: sections.map(\.letter)) { letter in
                    proxy.scrollTo(letter, anchor: .top)
                }
                .padding(.trailing, 2)
            }
        }
    }

    private func row(_ show: Show) -> some View {
        HStack(spacing: 12) {
            landscapeThumb(show)
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(show.name)
                .font(.body)
            Spacer(minLength: 12)
            let count = show.upcomingEpisodes.count
            if count > 0 {
                CountPill(count: count)
            }
        }
    }

    /// 16:9 landscape thumbnail from the show's backdrop, falling back to the
    /// poster (cropped) when no backdrop is available.
    private func landscapeThumb(_ show: Show) -> some View {
        let url = TMDBImage.backdrop(show.backdropPath, size: "w300")
            ?? TMDBImage.poster(show.posterPath, size: "w300")
        return CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Grouping

    private var sections: [(letter: String, shows: [Show])] {
        let groups = Dictionary(grouping: shows) { indexLetter(for: $0.name) }
        return groups.keys
            .sorted { lhs, rhs in
                if lhs == "#" { return false }   // non-letters sort last
                if rhs == "#" { return true }
                return lhs < rhs
            }
            .map { letter in
                (letter, groups[letter]!.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                })
            }
    }

    private func indexLetter(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first, first.isLetter else {
            return "#"
        }
        return String(first).uppercased()
    }

    // MARK: Delete

    private func delete(_ show: Show) {
        context.delete(show)
        try? context.save()
        Task { await EpisodeNotifier.refresh(context: context) }
    }
}

/// Vertical A–Z scrubber, sized to its content (not stretched to the list
/// height). Tapping or dragging over a letter reports it so the list can scroll
/// to that section; a light haptic fires as the letter changes.
private struct AlphaIndex: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var lastLetter: String?
    private let haptics = UISelectionFeedbackGenerator()
    private let rowHeight: CGFloat = 13

    var body: some View {
        VStack(spacing: 4) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tint)
                    .frame(height: rowHeight)
            }
        }
        .frame(width: 18)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in select(at: value.location.y) }
                .onEnded { _ in lastLetter = nil }
        )
    }

    private func select(at y: CGFloat) {
        guard !letters.isEmpty else { return }
        let index = min(max(Int(y / rowHeight), 0), letters.count - 1)
        let letter = letters[index]
        guard letter != lastLetter else { return }
        lastLetter = letter
        haptics.selectionChanged()
        onSelect(letter)
    }
}

#Preview {
    LibraryView()
        .modelContainer(Persistence.previewContainer())
}
