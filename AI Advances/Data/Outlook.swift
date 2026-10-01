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

    /// A short plain-language outlook written from the current forecasts.
    static func outlook(_ upcoming: [Forecast], shifts: [ForecastShift], now: Date) -> String {
        var parts: [String] = []
        let soon = upcoming.filter { $0.predicted! < now.addingTimeInterval(365.25 * 86_400) }
        if !soon.isEmpty {
            parts.append("Within the next year the trends point to: " + soon.prefix(4).map { "\($0.title) (\(Format.monthYear($0.predicted!)))" }.joined(separator: "; ") + ".")
        }
        let areas = Dictionary(grouping: upcoming.filter { $0.kind == .capabilities }, by: \.area)
            .mapValues { $0.map(\.predicted!).min()! }
            .sorted { $0.value < $1.value }
        if let next = areas.first, let last = areas.last, next.key != last.key {
            parts.append("Among capability areas, \(next.key.lowercased()) is closest to saturating its hardest tracked benchmarks; \(last.key.lowercased()) has the longest way to go.")
        }
        if let w = upcoming.first(where: { $0.id == "metr-week" }) {
            parts.append("AI agents are on course to handle week-long tasks around \(Format.monthYear(w.predicted!)).")
        }
        let earlier = shifts.filter { $0.months < 0 }.count, later = shifts.filter { $0.months > 0 }.count
        if earlier + later > 0 {
            parts.append(earlier >= later
                         ? "Over the last 3 months, \(earlier) of \(earlier + later) forecasts that moved came earlier: progress is speeding up relative to the trend."
                         : "Over the last 3 months, \(later) of \(earlier + later) forecasts that moved slipped later: progress is running behind the trend.")
        }
        return parts.joined(separator: " ")
    }
}
