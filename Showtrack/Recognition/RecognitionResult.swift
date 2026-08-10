import Foundation

/// What the recognizer extracts from a photo of a TV detail screen.
struct RecognitionResult: Sendable {
    var titleGuess: String
    var episodeTitleGuess: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    /// Every OCR line, kept for debugging / manual correction.
    var rawLines: [String]

    var isEmpty: Bool { titleGuess.trimmingCharacters(in: .whitespaces).isEmpty }
}
