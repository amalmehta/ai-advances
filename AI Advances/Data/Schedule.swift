import Foundation

/// The app refreshes once each morning, matching the website's pre-dawn rebuild.
enum MorningSchedule {
    static let hour = 7

    /// The most recent 7:00 AM at or before `now`, in the user's time zone.
    static func lastMorning(before now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
        return today <= now ? today : calendar.date(byAdding: .day, value: -1, to: today)!
    }

    /// The next 7:00 AM after `now`.
    static func nextMorning(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: lastMorning(before: now, calendar: calendar))!
    }

    /// Data is stale once a 7:00 AM has passed since it was last refreshed.
    static func needsRefresh(lastRefresh: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastRefresh else { return true }
        return lastRefresh < lastMorning(before: now, calendar: calendar)
    }
}
