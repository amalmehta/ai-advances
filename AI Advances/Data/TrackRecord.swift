import Foundation

/// How earlier forecasts did: on milestones that have since been reached, and on ones whose
/// likely range has run out without the milestone happening.
struct TrackRecord: Hashable {
    enum Outcome: String, Hashable {
        /// The milestone happened inside the likely range.
        case inside
        /// It happened before the range began.
        case early
        /// It happened after the range ended.
        case late
        /// It happened after the range began, and the range had no end: not scored either way.
        case openEnded
        /// The range ended before today and the milestone still hasn't happened.
        case expired
    }

    struct Item: Identifiable, Hashable {
        var id: String { forecastID + "|\(madeOn.timeIntervalSince1970)" }
        let forecastID: String
        let title: String
        /// When the milestone was reached; for `.expired` items, the scoring date (it hasn't been).
        let reached: Date
        /// When the scored forecast was made (at least `minLead` before the milestone).
        let madeOn: Date
        let predicted: Date
        let early: Date?
        let late: Date?
        /// Actual minus predicted, in months: positive means it happened later than forecast.
        /// For `.expired` items, how overdue it is so far (a lower bound).
        let errorMonths: Double
        let inside: Bool
        var outcome: Outcome = .inside
    }

    /// One forecast per reached milestone, the one made closest to six months ahead (a closed
    /// range preferred), for display.
    let items: [Item]
    /// Forecasts counted in the coverage figure: closed ranges on reached milestones plus expired
    /// ranges. At most one per milestone per calendar month, so a daily log doesn't count the
    /// same forecast thirty times.
    let scored: Int
    let inside: Int
    let medianAbsErrorMonths: Double?
    /// Every scored forecast (inside, early, late, expired; one per milestone per month), for calibration.
    let allItems: [Item]
    /// Forecasts on reached milestones whose range had no end, reported separately.
    var openEnded: Int = 0
    /// Scored forecasts whose range ended without the milestone being reached (counted as misses).
    var expired: Int = 0
    /// Distinct milestones with at least one scored or open-ended forecast.
    var milestones: Int = 0
    /// For each milestone that's overdue, the latest forecast whose range has run out.
    var missed: [Item] = []

    var coverage: Double? { scored == 0 ? nil : Double(inside) / Double(scored) }

    /// One sentence for the app, the website and Claude's fact sheet.
    var summary: String {
        guard let c = coverage else {
            return openEnded > 0
                ? "No forecast with a closed likely range has been tested yet (\(openEnded) open-ended \(openEnded == 1 ? "range" : "ranges") can't be scored)."
                : "No milestone has been reached since forecasts began, so there's no track record yet."
        }
        var s = "Past likely ranges contained the real date \(Format.percent(c)) of the time (\(inside) of \(scored) forecasts on \(milestones) \(milestones == 1 ? "milestone" : "milestones"), made at least 3 months ahead"
        if expired > 0 { s += ", counting \(expired) whose range ran out before the milestone arrived as \(expired == 1 ? "a miss" : "misses")" }
        s += ")"
        if openEnded > 0 { s += "; \(openEnded) more had no end date and \(openEnded == 1 ? "isn't" : "aren't") counted" }
        if let m = medianAbsErrorMonths { s += String(format: "; the typical miss was %.0f months", m) }
        return s + "."
    }

    static let minLead: TimeInterval = 90 * 86_400

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// One entry per calendar month: a live entry if there is one, else the earliest.
    private static func onePerMonth(_ items: [(Item, live: Bool)]) -> [Item] {
        let byMonth = Dictionary(grouping: items) { utc.dateComponents([.year, .month], from: $0.0.madeOn) }
        return byMonth.values.map { group in
            group.min { a, b in a.live != b.live ? a.live : a.0.madeOn < b.0.madeOn }!.0
        }
        .sorted { $0.madeOn < $1.madeOn }
    }

    static func score(history: [ForecastLogEntry], current: [Forecast], now: Date = Date()) -> TrackRecord {
        var items: [Item] = []
        var all: [Item] = []
        var open: [Item] = []
        var missed: [Item] = []
        var milestones = Set<String>()
        for f in current {
            if let reached = f.reached {
                let candidates = onePerMonth(history.compactMap { e in
                    guard e.asOf <= reached.addingTimeInterval(-minLead),
                          let s = e.forecasts[f.id], s.reached == nil, let p = s.predicted else { return nil }
                    let outcome: Outcome
                    if let early = s.early, reached < early { outcome = .early }
                    else if s.early == nil { outcome = s.late.map { reached <= $0 ? .inside : .late } ?? .openEnded }
                    else if let late = s.late { outcome = reached <= late ? .inside : .late }
                    else { outcome = .openEnded }
                    return (Item(forecastID: f.id, title: f.title, reached: reached, madeOn: e.asOf, predicted: p,
                                 early: s.early, late: s.late, errorMonths: Dates.months(from: p, to: reached),
                                 inside: outcome == .inside, outcome: outcome), !e.reconstructed)
                })
                guard !candidates.isEmpty else { continue }
                milestones.insert(f.id)
                let closed = candidates.filter { $0.outcome != .openEnded }
                all += closed
                open += candidates.filter { $0.outcome == .openEnded }
                let sixMonthsBefore = reached.addingTimeInterval(-182 * 86_400)
                let pool = closed.isEmpty ? candidates : closed
                if let best = pool.min(by: { abs($0.madeOn.timeIntervalSince(sixMonthsBefore)) < abs($1.madeOn.timeIntervalSince(sixMonthsBefore)) }) {
                    items.append(best)
                }
            } else if !f.inactive {
                // Not reached: every range that has already ended is a miss.
                let expired = onePerMonth(history.compactMap { e in
                    guard e.asOf <= now.addingTimeInterval(-minLead), let s = e.forecasts[f.id], s.reached == nil,
                          let p = s.predicted, let late = s.late, late < now else { return nil }
                    return (Item(forecastID: f.id, title: f.title, reached: now, madeOn: e.asOf, predicted: p,
                                 early: s.early, late: late, errorMonths: Dates.months(from: p, to: now),
                                 inside: false, outcome: .expired), !e.reconstructed)
                })
                guard let latest = expired.last else { continue }
                milestones.insert(f.id)
                all += expired
                missed.append(latest)
            }
        }
        // Typical miss over forecasts whose milestone has a real date.
        let errors = (all + open).filter { $0.outcome != .expired }.map { abs($0.errorMonths) }.sorted()
        let median = errors.isEmpty ? nil : errors.count % 2 == 1 ? errors[errors.count / 2]
            : (errors[errors.count / 2 - 1] + errors[errors.count / 2]) / 2
        return TrackRecord(items: items.sorted { $0.reached > $1.reached }, scored: all.count,
                           inside: all.filter(\.inside).count, medianAbsErrorMonths: median, allItems: all,
                           openEnded: open.count, expired: all.filter { $0.outcome == .expired }.count,
                           milestones: milestones.count, missed: missed.sorted { $0.title < $1.title })
    }
}
