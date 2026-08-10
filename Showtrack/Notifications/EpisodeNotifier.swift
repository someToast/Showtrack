import Foundation
import SwiftData
import UserNotifications

/// Schedules a local notification for each upcoming episode of a tracked show,
/// firing at 9am local time on the episode's air date.
///
/// Local notifications need no special entitlement. Identifiers are stable
/// (`episode-<tmdbID>`) so `refresh()` replaces rather than duplicates, and we
/// cap the count to stay under iOS's 64 pending-request limit.
@MainActor
enum EpisodeNotifier {
    private static let idPrefix = "episode-"
    private static let notifyHour = 9
    private static let maxScheduled = 60

    /// Ask for permission. Call at a contextual moment (e.g. after the first add).
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Rebuild the schedule from the current library. No-ops if unauthorized.
    static func refresh(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        // Clear our previously-scheduled requests.
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ourIDs)

        // Upcoming episodes of tracked shows (small library → filter in Swift to
        // avoid optional-relationship predicate pitfalls).
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.airDate)])
        let all = (try? context.fetch(descriptor)) ?? []
        let upcoming = all.filter { ep in
            guard let air = ep.airDate, air >= startOfToday else { return false }
            return ep.show?.isTracking ?? false
        }.prefix(maxScheduled)

        for episode in upcoming {
            guard let request = makeRequest(for: episode) else { continue }
            try? await center.add(request)
        }
    }

    // MARK: Building requests

    private static func makeRequest(for episode: Episode) -> UNNotificationRequest? {
        guard let air = episode.airDate, let show = episode.show else { return nil }

        // Air dates are stored as a UTC calendar day. Extract Y/M/D in UTC, then
        // fire at 9am *local* on that day.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let ymd = utc.dateComponents([.year, .month, .day], from: air)

        var fireComponents = DateComponents()
        fireComponents.year = ymd.year
        fireComponents.month = ymd.month
        fireComponents.day = ymd.day
        fireComponents.hour = notifyHour

        // Skip anything whose fire time is already in the past (e.g. today, 9am gone).
        guard let fireDate = Calendar.current.date(from: fireComponents), fireDate > .now else {
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = show.name
        let code = episode.seasonEpisodeCode
        content.body = episode.name.isEmpty
            ? "\(code) is out today."
            : "\(code) “\(episode.name)” is out today."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
        return UNNotificationRequest(
            identifier: "\(idPrefix)\(episode.tmdbID)",
            content: content,
            trigger: trigger
        )
    }
}
