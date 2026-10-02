import Foundation

/// How old the hand-researched content (lab notes, highlights) is. The data-driven pages update
/// themselves; these only change when someone re-researches them.
struct Freshness: Hashable {
    static let staleAfterDays = 45

    let date: Date
    let days: Int

    var isStale: Bool { days > Self.staleAfterDays }

    init?(_ date: Date?, now: Date = Date()) {
        guard let date else { return nil }
        self.date = date
        days = max(0, Int(now.timeIntervalSince(date) / 86_400))
    }

    /// e.g. "Researched Sep 30, 2026 (12 days ago)."
    func sentence(_ what: String) -> String {
        let age = days == 0 ? "today" : days == 1 ? "1 day ago" : "\(days) days ago"
        let base = "\(what) \(Format.date.string(from: date)) (\(age))."
        return isStale ? base + " It may be out of date: the data-driven parts of this page are current, but these notes only change when they're re-researched." : base
    }

    static func labNotes(_ notes: [LabNote]) -> Date? { notes.compactMap { Dates.parse($0.asOf) }.min() }
    static func highlights(_ advances: [Advance]) -> Date? { advances.map(\.day).max() }
}
