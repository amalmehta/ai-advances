import Foundation

struct ForecastShift: Identifiable, Hashable {
    var id: String { forecast.id }
    let forecast: Forecast
    /// Negative = the predicted date moved earlier.
    let months: Double
    let since: Date
}

extension Forecasts {
    /// How each upcoming forecast's date moved compared with the logged forecast nearest `monthsBack` ago.
    static func shifts(_ upcoming: [Forecast], history: [ForecastLogEntry], now: Date, monthsBack: Int = 3) -> [ForecastShift] {
        let target = Calendar.current.date(byAdding: .month, value: -monthsBack, to: now)!
        guard let then = history.min(by: { abs($0.asOf.timeIntervalSince(target)) < abs($1.asOf.timeIntervalSince(target)) })
        else { return [] }
        return upcoming.compactMap { f in
            guard let old = then.forecasts[f.id]?.predicted, let new = f.predicted else { return nil }
            let m = Dates.months(from: old, to: new)
            return abs(m) >= 1 ? ForecastShift(forecast: f, months: m, since: then.asOf) : nil
        }
        .sorted { abs($0.months) > abs($1.months) }
    }

    /// A short plain-language outlook written from the current forecasts. `all` (every current
    /// forecast, reached ones included) lets it name capability areas whose tracked benchmarks
    /// are all past the target.
    static func outlook(_ upcoming: [Forecast], shifts: [ForecastShift], now: Date, all: [Forecast] = []) -> String {
        var parts: [String] = []
        let soon = upcoming.filter { $0.predicted! < now.addingTimeInterval(365.25 * 86_400) }
        if !soon.isEmpty {
            parts.append("Within the next year the trends point to: " + soon.prefix(4).map { "\($0.title) (\(Format.monthYear($0.predicted!)))" }.joined(separator: "; ") + ".")
        }
        // Each area's nearest upcoming benchmark milestone.
        let nearest = Dictionary(grouping: upcoming.filter { $0.kind == .capabilities }, by: \.area)
            .mapValues { $0.min { $0.predicted! < $1.predicted! }! }
            .sorted { $0.value.predicted! < $1.value.predicted! }
        if let next = nearest.first, let last = nearest.last, next.key != last.key {
            parts.append("Among capability areas, \(next.key.lowercased()) has the nearest upcoming benchmark milestone (\(next.value.title), around \(Format.monthYear(next.value.predicted!))); in \(last.key.lowercased()) the nearest one is furthest off (\(Format.monthYear(last.value.predicted!))).")
        }
        // Areas with nothing left to forecast: every benchmark Epoch still updates is past its target.
        let done = Dictionary(grouping: all.filter { $0.kind == .capabilities }, by: \.area)
            .filter { _, fs in fs.allSatisfy { $0.reached != nil || $0.inactive } && fs.contains { $0.reached != nil } }
            .keys.sorted()
        if !done.isEmpty {
            parts.append("In \(done.map { $0.lowercased() }.joined(separator: " and ")), every tracked benchmark Epoch still updates has already passed its target.")
        }
        if let w = upcoming.first(where: { $0.id == "metr-week" }) {
            parts.append("AI agents are on course to handle week-long tasks around \(Format.monthYear(w.predicted!)).")
        }
        let earlier = shifts.filter { $0.months < 0 }.count, later = shifts.filter { $0.months > 0 }.count
        if earlier + later > 0, let since = shifts.map(\.since).min() {
            let when = "Compared with the forecasts made in \(Format.monthYear(since))"
            parts.append(earlier >= later
                         ? "\(when), \(earlier) of \(earlier + later) forecasts that moved came earlier: progress is speeding up relative to the trend."
                         : "\(when), \(later) of \(earlier + later) forecasts that moved slipped later: progress is running behind the trend.")
        }
        return parts.joined(separator: " ")
    }
}
