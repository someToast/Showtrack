import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// TMDB API credentials — setup instructions.
//
// The real credential lives in `Secrets.swift`, which is GITIGNORED so tokens
// never get committed. This template file is documentation only (it defines no
// type on purpose, so it never collides with the real `Secrets`).
//
// To set up:
//   1. Create a free account at https://www.themoviedb.org
//   2. Settings → API → request an API key (choose "Developer").
//   3. Copy the "API Read Access Token" (a long JWT-looking string).
//   4. Paste it into `Secrets.swift`:
//
//          enum Secrets {
//              static let tmdbAccessToken = "eyJ...your token..."
//          }
//
// Until a token is set, TMDBClient throws `TMDBError.missingToken` and search
// returns nothing — the rest of the app still builds and runs.
// ─────────────────────────────────────────────────────────────────────────────
