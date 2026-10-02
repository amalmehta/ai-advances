import Foundation

/// How earlier forecasts did on milestones that have since been reached.
struct TrackRecord: Hashable {
    struct Item: Identifiable, Hashable {
        var id: String { forecastID }
        let forecastID: String
        let title: String
        let reached: Date
        /// When the scored forecast was made (at least `minLead` before the milestone).
        let madeOn: Date
        let predicted: Date
        let early: Date?
        let late: Date?
        /// Actual minus predicted, in months: positive means it happened later than forecast.
        let errorMonths: Double
        let inside: Bool
    }

    /// One scored forecast per milestone: the one made closest to six months ahead.
    let items: [Item]
    /// Every qualifying forecast in the history, for the coverage figures.
    let scored: Int
    let inside: Int
    let medianAbsErrorMonths: Double?

    var coverage: Double? { scored == 0 ? nil : Double(inside) / Double(scored) }

    /// One sentence for the app, the website and Claude's fact sheet.
    var summary: String {
        guard let c = coverage else { return "No milestone has been reached since forecasts began, so there's no track record yet." }
        return "Past likely ranges contained the real date \(Format.percent(c)) of the time (\(inside) of \(scored) forecasts made at least 3 months ahead)"
            + (medianAbsErrorMonths.map { String(format: "; the typical miss was %.0f months.", $0) } ?? ".")
    }

    static let minLead: TimeInterval = 90 * 86_400

    static func score(history: [ForecastLogEntry], current: [Forecast]) -> TrackRecord {
        var items: [Item] = []
        var all: [Item] = []
        for f in current {
            guard let reached = f.reached else { continue }
            let candidates: [Item] = history.compactMap { e in
                guard e.asOf <= reached.addingTimeInterval(-minLead),
                      let s = e.forecasts[f.id], s.reached == nil, let p = s.predicted else { return nil }
                let inside = (s.early.map { $0 <= reached } ?? false) && (s.late.map { reached <= $0 } ?? true)
                return Item(forecastID: f.id, title: f.title, reached: reached, madeOn: e.asOf, predicted: p,
                            early: s.early, late: s.late, errorMonths: Dates.months(from: p, to: reached), inside: inside)
            }
            all += candidates
            let sixMonthsBefore = reached.addingTimeInterval(-182 * 86_400)
            if let best = candidates.min(by: { abs($0.madeOn.timeIntervalSince(sixMonthsBefore)) < abs($1.madeOn.timeIntervalSince(sixMonthsBefore)) }) {
                items.append(best)
            }
        }
        let errors = all.map { abs($0.errorMonths) }.sorted()
        let median = errors.isEmpty ? nil : errors.count % 2 == 1 ? errors[errors.count / 2]
            : (errors[errors.count / 2 - 1] + errors[errors.count / 2]) / 2
        return TrackRecord(items: items.sorted { $0.reached > $1.reached }, scored: all.count,
                           inside: all.filter(\.inside).count, medianAbsErrorMonths: median)
    }
}
