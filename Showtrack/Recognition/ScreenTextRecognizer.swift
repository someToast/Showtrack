import Foundation
import Vision
import FoundationModels
import UIKit

/// Structured output for the on-device model. Must be at file scope (not nested
/// `private`) so the `@Generable` macro's generated conformance can reach it.
@Generable
struct ShowGuess {
    @Guide(description: "The show's name ONLY — usually 1–5 words. Never a sentence, description, or synopsis, and no season/episode text.")
    var seriesTitle: String
    @Guide(description: "The individual episode's title, or an empty string if not shown")
    var episodeTitle: String
    @Guide(description: "The season number if visible, otherwise 0")
    var seasonNumber: Int
    @Guide(description: "The episode number if visible, otherwise 0")
    var episodeNumber: Int
}

/// Turns a photo of a TV detail screen into a best-guess show identity.
///
/// Pipeline: Vision OCR → parse. The parse step prefers Apple's on-device
/// Foundation Models to pick the *series* title out of the noisy OCR text;
/// if the model is unavailable (e.g. Apple Intelligence off, or in a simulator)
/// it falls back to a size-based heuristic (the largest text is usually the
/// title) plus a regex for the season/episode code.
enum ScreenTextRecognizer {

    static func recognize(_ image: UIImage) async -> RecognitionResult {
        let lines = (try? await ocr(image)) ?? []
        let texts = lines.map(\.text)
        let sne = parseSeasonEpisode(from: texts)

        if let ai = try? await aiParse(lines: lines), isPlausibleTitle(ai.seriesTitle) {
            return RecognitionResult(
                titleGuess: ai.seriesTitle,
                episodeTitleGuess: ai.episodeTitle.isEmpty ? nil : ai.episodeTitle,
                seasonNumber: ai.seasonNumber > 0 ? ai.seasonNumber : sne?.season,
                episodeNumber: ai.episodeNumber > 0 ? ai.episodeNumber : sne?.episode,
                rawLines: texts
            )
        }

        return RecognitionResult(
            titleGuess: heuristicTitle(from: lines),
            episodeTitleGuess: nil,
            seasonNumber: sne?.season,
            episodeNumber: sne?.episode,
            rawLines: texts
        )
    }

    /// Rejects an over-long "title" (the model occasionally returns synopsis
    /// text) so we fall back to the largest-text heuristic instead.
    private static func isPlausibleTitle(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.count <= 60 && trimmed.split(separator: " ").count <= 10
    }

    // MARK: OCR

    private struct OCRLine: Sendable {
        let text: String
        /// Lower-confidence readings of the same line — a stylized logo often
        /// reads better in an alternate than in the top candidate.
        let alternates: [String]
        /// Normalized bounding-box height, a proxy for on-screen prominence.
        let height: CGFloat
    }

    private static func ocr(_ image: UIImage) async throws -> [OCRLine] {
        guard let cgImage = image.cgImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)
        return observations.compactMap { obs in
            let candidates = obs.topCandidates(3).map(\.string)
            guard let primary = candidates.first else { return nil }
            return OCRLine(
                text: primary,
                alternates: Array(candidates.dropFirst()),
                height: obs.boundingBox.cgRect.height
            )
        }
    }

    // MARK: On-device parse (Foundation Models)

    private static func aiParse(lines: [OCRLine]) async throws -> ShowGuess? {
        guard !lines.isEmpty else { return nil }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let maxHeight = lines.map(\.height).max() ?? 0
        let fragments = lines.map { line -> String in
            let pct = maxHeight > 0 ? Int((line.height / maxHeight * 100).rounded()) : 0
            let alts = line.alternates.isEmpty
                ? ""
                : " (also read as: \(line.alternates.joined(separator: ", ")))"
            return "- [size \(pct)%] \(line.text)\(alts)"
        }.joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: """
            You identify the COMPLETE TV series title from noisy OCR text captured by photographing \
            a TV detail screen. Each fragment is tagged with its on-screen text size relative to the \
            largest ([size 100%] is biggest). Follow these rules:
            - The title is the largest text and frequently spans the top ONE OR TWO prominent lines: \
            a main title plus a SUBTITLE directly beneath it. The subtitle is smaller than the main \
            title but still much larger than body text, and often begins with words like "Into", \
            "The", "A", or follows a colon.
            - Assemble the FULL title from those prominent top lines in top-to-bottom reading order. \
            If a subtitle is present, INCLUDE it, joining main title and subtitle with ": ".
            - Never output only a fragment or sub-phrase, and never drop the main title.
            - A single stylized title may be split across stacked lines, and letters in logo fonts \
            are often misread (an alternate reading is given when available) — combine the fragments \
            and correct obvious OCR errors into a real, well-known title.
            - Ignore UI labels (Play, Resume, Watchlist, Download), star/content ratings, runtimes, \
            audio and quality badges (HD, Spatial Audio, AD), rankings ("Top 10", "#6 in ..."), \
            standalone years, and cast/creator/synopsis lines.
            """
        )
        let prompt = """
        OCR fragments, top to bottom:
        \(fragments)

        Give the complete series title and any visible season/episode numbers.
        """
        let response = try await session.respond(to: prompt, generating: ShowGuess.self)
        return response.content
    }

    // MARK: Heuristic fallback

    private static func heuristicTitle(from lines: [OCRLine]) -> String {
        lines
            .filter { line in
                let t = line.text.trimmingCharacters(in: .whitespaces)
                return t.count >= 2 && !isSeasonEpisodeCode(t)
            }
            .max(by: { $0.height < $1.height })?
            .text ?? ""
    }

    private static func isSeasonEpisodeCode(_ s: String) -> Bool {
        (try? Regex(#"^[Ss]\d{1,2}\s*[Ee]\d{1,3}$"#))
            .map { s.wholeMatch(of: $0) != nil } ?? false
    }

    // MARK: Season/episode regex

    private static func parseSeasonEpisode(from lines: [String]) -> (season: Int, episode: Int)? {
        let text = lines.joined(separator: " ")
        let patterns = [
            #"[Ss](\d{1,2})\s*[Ee](\d{1,3})"#,                        // S2E5, s02 e05
            #"(?:Season|Series)\s*(\d{1,2}).*?Episode\s*(\d{1,3})"#,  // Season 2 … Episode 5
            #"\b(\d{1,2})\s*[xX]\s*(\d{1,3})\b"#                      // 2x05
        ]
        for pattern in patterns {
            guard let regex = try? Regex(pattern),
                  let match = text.firstMatch(of: regex),
                  match.count >= 3,
                  let sSub = match[1].substring, let eSub = match[2].substring,
                  let season = Int(sSub), let episode = Int(eSub)
            else { continue }
            return (season, episode)
        }
        return nil
    }
}
