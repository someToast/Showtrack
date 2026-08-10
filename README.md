# Showtrack

An iOS app for keeping up with currently-airing episodic TV — network and
streaming — on one screen. Showtrack shows what's releasing **today** and
**this week** as a grid of poster art, and its headline feature is adding a show
by **photographing its detail screen off a TV**: on-device OCR + Apple's
Foundation Models resolve the (often stylized) title, which you confirm and add.

Built with SwiftUI, SwiftData + CloudKit, and Apple's on-device Vision and
Foundation Models frameworks.

## Features

- **Today / This Week** — a vertical, two-column grid of upcoming episodes, each
  poster badged with its air date, a premiere/finale marker, and the provider.
- **Scan to add** — point the camera at a show's info screen on a TV; Vision OCR
  reads the text and an on-device language model reconstructs the series title
  (handles stylized logos and split main-title/subtitle layouts), then searches
  TMDB so you can confirm the match.
- **Manual add** — search TMDB by name as a fallback.
- **Library** — every tracked show, alphabetized with an A–Z scrubber and an
  upcoming-episode count; tap through to a series detail with the full schedule.
- **Episode & show detail** — artwork, synopsis, provider, and dates formatted
  as "Thursday, August 13".
- **Local notifications** when a tracked episode drops.
- **Provider icons** chosen from TMDB + JustWatch data with a general,
  network-aware rule set (no per-provider special cases): a show resolves to its
  originating network's own tile, its exact streaming service, or a rendered
  network wordmark — keeping distinct services (e.g. AMC vs AMC+, NBC vs Peacock)
  apart.
- **iCloud sync** via SwiftData + CloudKit, with a graceful local-store fallback.

## Requirements

- Xcode 26 (iOS 26 SDK); deployment target iOS 26.0.
- A device running iOS 26+ for the camera scan and on-device recognition
  (the simulator has no camera and falls back to the photo library).
- A free TMDB API Read Access Token.

## Setup

1. Open the project:

   ```bash
   open Showtrack.xcodeproj
   ```

2. Add your TMDB credential. Create `Showtrack/Services/Secrets.swift` (it's
   gitignored so tokens are never committed) with:

   ```swift
   enum Secrets {
       static let tmdbAccessToken = "your-TMDB-v4-read-access-token"
   }
   ```

   Get a free token at [themoviedb.org](https://www.themoviedb.org) →
   Settings → API → request a *Developer* key → copy the **API Read Access
   Token** (the long JWT-style string). Without a token the app still builds and
   runs; searches just return nothing.

3. In **Signing & Capabilities**, select your own development team. The project
   ships with no team set. Without a valid team the app still runs in the
   simulator via a local SwiftData store (CloudKit falls back automatically); a
   device build and iCloud sync require your team and its iCloud container.

## Project layout

```
Showtrack/
  App/           app entry
  Models/        SwiftData Show / Episode
  Services/      TMDB client, image URLs, importer + provider selection, notifications
  Recognition/   camera, Vision OCR + Foundation Models parsing
  Views/         Home, Library, Add, detail screens, cards
  Support/       assets, Info.plist, entitlements, app icon
```

`Showtrack.xcodeproj` is the source of truth — edit target settings, signing,
and capabilities directly in Xcode; add source files through Xcode.

## Attribution

This product uses the [TMDB](https://www.themoviedb.org) API but is not endorsed
or certified by TMDB. Streaming-availability data is provided by JustWatch.
Network and provider logos are trademarks of their respective owners and are
used here for identification only.
