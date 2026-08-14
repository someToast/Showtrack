import SwiftUI
import SwiftData
import UIKit

/// Add a show either by scanning a TV screen (camera → OCR → parse) or by
/// searching manually. Both paths land on the same TMDB result list, which the
/// user taps to confirm and import.
struct AddShowView: View {
    /// A pre-captured screen photo to process on appear. Used by the Home
    /// scan flow so the camera isn't presented as a nested sheet; everything
    /// after recognition is the normal add flow.
    var initialImage: UIImage?

    /// When shown as a tab (vs. a sheet) there's no Cancel button, and a
    /// successful add calls `onFinished` (e.g. to switch tabs) instead of
    /// dismissing.
    var embedded = false
    var onFinished: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var searchedQuery = ""
    @State private var results: [TMDBShow] = []
    @State private var isSearching = false
    @State private var isRecognizing = false
    @State private var importingID: Int?
    @State private var errorMessage: String?
    @State private var recognitionNote: String?
    @State private var scannedLines: [String] = []
    /// Drives the search field's focus/keyboard. Raised on the Add tab so the
    /// user can start typing immediately.
    @State private var searchPresented = false

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
                if let recognitionNote {
                    Section {
                        Label(recognitionNote, systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #if DEBUG
                if !scannedLines.isEmpty {
                    Section("OCR lines (\(scannedLines.count))") {
                        ForEach(Array(scannedLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                #endif
                ForEach(results) { show in
                    ResultRow(show: show, isImporting: importingID == show.id) {
                        Task { await add(show) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .overlay { statusOverlay }
            .searchable(text: $query, isPresented: $searchPresented, prompt: "Search TV shows")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Add Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task {
                if let initialImage {
                    await handleCaptured(initialImage)
                } else {
                    // Manual add (the Add tab): focus search and raise the keyboard.
                    searchPresented = true
                }
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isRecognizing {
            ContentUnavailableView {
                Label("Reading screen…", systemImage: "text.viewfinder")
            } description: {
                Text("Identifying the show from your photo.")
            }
            .background(.background)
        } else if isSearching {
            ProgressView()
        } else if searchedQuery.isEmpty {
            // Shown until the user has typed text AND submitted a search.
            ContentUnavailableView {
                Label("Add a show", systemImage: "tv")
            } description: {
                Text("Search by show name.")
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: searchedQuery)
        }
    }

    // MARK: Actions

    private func handleCaptured(_ image: UIImage) async {
        errorMessage = nil
        recognitionNote = nil
        isRecognizing = true
        let result = await ScreenTextRecognizer.recognize(image)
        isRecognizing = false

        scannedLines = result.rawLines

        guard !result.isEmpty else {
            recognitionNote = "Couldn't read a show name — try searching by name."
            return
        }
        recognitionNote = "Scanned “\(result.titleGuess)” — pick the right match below."
        query = result.titleGuess
        await search()
    }

    private func search() async {
        errorMessage = nil
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await TMDBClient.shared.searchTV(query)
            searchedQuery = query
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ show: TMDBShow) async {
        errorMessage = nil
        importingID = show.id
        defer { importingID = nil }
        do {
            try await ShowImporter(context: context).importShow(show)
            await EpisodeNotifier.requestAuthorization()
            await EpisodeNotifier.refresh(context: context)
            finish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        if let onFinished { onFinished() } else { dismiss() }
    }
}

private struct ResultRow: View {
    let show: TMDBShow
    let isImporting: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PosterView(path: show.posterPath)
                .frame(width: 46, height: 69)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(show.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let year = show.firstAirDate?.prefix(4), !year.isEmpty {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isImporting {
                ProgressView()
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    AddShowView()
        .modelContainer(Persistence.previewContainer(seeded: false))
}
