import Foundation

/// Ordinary least squares on (years, transformed value), with the slope's standard error and
/// the scatter around the line, so a forecast can carry an honest range, not just a date.
struct LinearFit: Hashable {
    let slope: Double
    let intercept: Double
    let slopeSE: Double
    /// Standard deviation of the points around the line, in y units.
    let residualSD: Double
    let n: Int
    let xMean: Double
    let yMean: Double

    static func fit(_ pts: [(x: Double, y: Double)]) -> LinearFit? {
        guard pts.count >= 4 else { return nil }
        let n = Double(pts.count)
        let mx = pts.map(\.x).reduce(0, +) / n
        let my = pts.map(\.y).reduce(0, +) / n
        let sxx = pts.map { ($0.x - mx) * ($0.x - mx) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let slope = pts.map { ($0.x - mx) * ($0.y - my) }.reduce(0, +) / sxx
        let intercept = my - slope * mx
        let sse = pts.map { (p: (x: Double, y: Double)) -> Double in
            let e = p.y - (intercept + slope * p.x)
            return e * e
        }.reduce(0, +)
        let sd = (sse / (n - 2)).squareRoot()
        return LinearFit(slope: slope, intercept: intercept, slopeSE: sd / sxx.squareRoot(), residualSD: sd,
                         n: pts.count, xMean: mx, yMean: my)
    }

    /// When the line reaches `target`; nil if it never does going forward.
    func x(reaching target: Double, slope s: Double? = nil) -> Double? {
        let s = s ?? slope
        guard s > 0 else { return nil }
        return xMean + (target - yMean) / s
    }

    /// Likely range (nominally 90%). Two sources of uncertainty: the slope (steepest and shallowest plausible lines,
    /// pivoting on the data's centre) and the scatter of records around the line, which moves the
    /// crossing by about ±z·σ/slope. Without the scatter term the ranges caught the real date only
    /// ~30% of the time in hindcasts. The late end is nil when the shallow slope never gets there.
    func range(reaching target: Double, z: Double = 1.645) -> (early: Double?, late: Double?) {
        guard slope > 0 else { return (nil, nil) }
        let scatter = z * residualSD / slope
        return (x(reaching: target, slope: slope + z * slopeSE).map { $0 - scatter },
                x(reaching: target, slope: slope - z * slopeSE).map { $0 + scatter })
    }
}

struct Forecast: Identifiable, Hashable {
    enum Kind: String, CaseIterable { case capabilities = "Capabilities", agents = "Agents", cost = "Cost", scale = "Scale" }

    let id: String
    let kind: Kind
    let area: String
    let title: String
    let target: String
    let current: String
    let basis: String
    /// Set when the target has already been hit; the date it happened.
    let reached: Date?
    let predicted: Date?
    let early: Date?
    let late: Date?
    /// Why there's no date: the trend never gets there, or it says the target is overdue.
    let note: String?

    var snapshot: ForecastSnapshot { ForecastSnapshot(predicted: predicted, early: early, late: late, reached: reached) }
}

struct ForecastSnapshot: Codable, Hashable {
    let predicted: Date?
    let early: Date?
    let late: Date?
    let reached: Date?
}

/// One recalculation of every forecast. Live entries are saved as they happen; reconstructed
/// ones are recomputed from only the data that existed on that date.
struct ForecastLogEntry: Codable, Hashable, Identifiable {
    var id: Date { asOf }
    let asOf: Date
    let reconstructed: Bool
    let forecasts: [String: ForecastSnapshot]
}

enum Forecasts {
    static let horizonTargets: [(minutes: Double, label: String, id: String)] = [
        (40 * 60, "a full work-week (40 hours)", "metr-week"),
        (167 * 60, "a full work-month (167 hours)", "metr-month"),
    ]
    static let computeTargets: [Double] = [1e28, 1e29]
    static let saturation = 0.9
    /// Furthest a forecast date is allowed to sit before it's reported as "not on the current trend".
    static let maxYearsOut = 15.0
    /// Width of the likely range, in standard errors, calibrated on past forecasts
    /// (CalibrationExperiment, Oct 2026): over 18 months of reconstructed forecasts, z = 2.75 put
    /// 84% of real dates inside the range (the old 1.645 put 58%). Tested on milestones it wasn't
    /// tuned on, coverage was about 2 in 3, because some misses are regime changes (a benchmark
    /// stalling, or jumping years early) that no smooth trend anticipates.
    static let calibratedZ = 2.75
    /// A variable only so the calibration experiment can sweep it.
    nonisolated(unsafe) static var rangeZ = calibratedZ

    private static func date(_ years: Double?) -> Date? {
        years.map { Date(timeIntervalSinceReferenceDate: $0 * 365.25 * 86_400) }
    }

    private static func logit(_ p: Double) -> Double {
        let q = min(max(p, 0.01), 0.99)
        return log(q / (1 - q))
    }

    /// Restricts everything to what was public on `asOf`, for reconstructing past forecasts.
    static func dataset(_ d: Dataset, asOf: Date) -> Dataset {
        var c = d
        c.results = d.results.filter { $0.releaseDate <= asOf }
        c.horizons = d.horizons.filter { $0.releaseDate <= asOf }
        c.notable = d.notable.filter { $0.date <= asOf }
        c.listed = d.listed.filter { $0.created <= asOf }
        return c
    }

    static func all(_ data: Dataset, profiles: [ModelProfile], asOf: Date) -> [Forecast] {
        var out: [Forecast] = []
        out += horizon(data, asOf: asOf)
        out += compute(data, asOf: asOf)
        out += price(profiles, asOf: asOf)
        out += saturationForecasts(data, asOf: asOf)
        return out
    }

    private static func make(id: String, kind: Forecast.Kind, area: String, title: String, target: String,
                             current: String, basis: String, reached: Date?, fit: LinearFit?, targetY: Double,
                             asOf: Date) -> Forecast {
        var predicted: Date?, early: Date?, late: Date?, note: String?
        if reached == nil {
            let now = Dates.years(asOf)
            let limit = now + maxYearsOut
            if let fit, let p = fit.x(reaching: targetY) {
                if p < now {
                    // The trend says this should already have happened: progress has stalled.
                    note = "Behind trend: the fit says it was due by \(Format.monthYear(date(p)!)), but no record has got there"
                } else if p > limit {
                    note = "More than \(Int(maxYearsOut)) years out on the current trend"
                } else {
                    let r = fit.range(reaching: targetY, z: rangeZ)
                    predicted = date(p)
                    early = date(min(p, max(r.early ?? p, now)))
                    late = date(r.late.flatMap { $0 <= limit ? max($0, p) : nil })
                }
            } else {
                note = fit == nil ? "Too few data points to fit a trend" : "No upward trend in the data"
            }
        }
        return Forecast(id: id, kind: kind, area: area, title: title, target: target, current: current, basis: basis,
                        reached: reached, predicted: predicted, early: early, late: late, note: note)
    }

    // MARK: Task horizon

    static func horizon(_ data: Dataset, asOf: Date) -> [Forecast] {
        let since = Dates.parse("2023-01-01")!
        let frontier = Analysis.horizonFrontier(data.horizons)
        let pts = frontier.filter { $0.releaseDate >= since }.map { (x: Dates.years($0.releaseDate), y: log10($0.minutes)) }
        let fit = LinearFit.fit(pts)
        let doubling = fit.map { 12 * log10(2) / $0.slope }
        return horizonTargets.map { t in
            make(id: t.id, kind: .agents, area: "Agents & real work",
                 title: "AI handles tasks taking \(t.label)",
                 target: "METR 50% time horizon ≥ \(Int(t.minutes / 60)) hours",
                 current: frontier.last.map { "\(Format.minutes($0.minutes)) now (\($0.modelGroup))" } ?? "no data",
                 basis: "Exponential fit to \(pts.count) record-setting models since 2023" + (doubling.map { ", doubling every \(Format.months($0))" } ?? ""),
                 reached: frontier.first { $0.minutes >= t.minutes }?.releaseDate,
                 fit: fit, targetY: log10(t.minutes), asOf: asOf)
        }
    }

    // MARK: Compute

    static func compute(_ data: Dataset, asOf: Date) -> [Forecast] {
        let since = Dates.parse("2020-01-01")!
        let models = data.notable.filter { $0.isFrontier && $0.date >= since && $0.computeFLOP != nil }
        let pts = models.map { (x: Dates.years($0.date), y: log10($0.computeFLOP!)) }
        let fit = LinearFit.fit(pts)
        let biggest = data.notable.filter { $0.computeFLOP != nil }.max { $0.computeFLOP! < $1.computeFLOP! }
        return computeTargets.map { t in
            let e = Int(log10(t).rounded())
            return make(id: "compute-1e\(e)", kind: .scale, area: "Compute",
                        title: "A training run reaches 10^\(e) FLOP",
                        target: "Largest known training run ≥ 10^\(e) FLOP",
                        current: biggest.map { "\(Format.flop($0.computeFLOP!)) now (\($0.name))" } ?? "no data",
                        basis: "Exponential fit to \(pts.count) frontier training runs since 2020" + (fit.map { String(format: ", %.1f× per year", pow(10, $0.slope)) } ?? ""),
                        reached: data.notable.filter { ($0.computeFLOP ?? 0) >= t }.map(\.date).min(),
                        fit: fit, targetY: log10(t), asOf: asOf)
        }
    }

    // MARK: Price

    static func price(_ profiles: [ModelProfile], asOf: Date) -> [Forecast] {
        let target = 0.01
        let steps = Analysis.cheapestOverTime(profiles, benchmark: "GPQA diamond", threshold: 0.8)
        // Falling prices: fit on -log10 so "reaching" works with a positive slope.
        let pts = steps.map { (x: Dates.years($0.date), y: -log10($0.price)) }
        let fit = LinearFit.fit(pts)
        return [make(id: "price-gpqa80", kind: .cost, area: "Cost",
                     title: "GPQA ≥ 80% costs under $0.01 per million tokens",
                     target: "Cheapest model scoring ≥ 80% on GPQA Diamond under $0.01 / M tokens",
                     current: steps.last.map { "\(Format.price($0.price)) now (\($0.model))" } ?? "no priced model yet",
                     basis: "Exponential fit to \(pts.count) successive price drops" + (fit.map { String(format: ", falling %.0f× per year", pow(10, $0.slope)) } ?? ""),
                     reached: steps.first { $0.price < target }?.date,
                     fit: fit, targetY: -log10(target), asOf: asOf)]
    }

    // MARK: Benchmark saturation

    /// When each tracked benchmark's best score reaches 90%, from an S-curve (linear in logit)
    /// fitted to the record-setting results of the last two years.
    static func saturationForecasts(_ data: Dataset, asOf: Date) -> [Forecast] {
        let since = asOf.addingTimeInterval(-2 * 365.25 * 86_400)
        return data.areas.flatMap { area in
            area.benchmarks.compactMap { b -> Forecast? in
                let f = Analysis.frontier(data.results, benchmark: b)
                guard let last = f.last else { return nil }
                let ceiling = data.benchmarks.first { $0.name == b }?.ceiling ?? 1
                let target = saturation * ceiling
                var pts = f.filter { $0.date >= since }.map { (x: Dates.years($0.date), y: logit($0.score / ceiling)) }
                // Anchor the start of the window with the record standing at that time.
                if let start = Analysis.frontierValue(f, at: since) { pts.insert((Dates.years(since), logit(start / ceiling)), at: 0) }
                let name = Analysis.shortName(b)
                return make(id: "sat-" + b, kind: .capabilities, area: area.name,
                            title: "\(name) reaches \(Format.percent(target))",
                            target: "Best score on \(name) ≥ \(Format.percent(target))",
                            current: "\(Format.percent(last.score, digits: 1)) now (\(last.model))",
                            basis: "S-curve fit to \(pts.count) records over the last two years",
                            reached: f.first { $0.score >= target }?.date,
                            fit: LinearFit.fit(pts), targetY: logit(saturation), asOf: asOf)
            }
        }
    }

    // MARK: History

    /// Forecasts recomputed at the start of each of the last `months` months. 18 months gives the
    /// track record enough past forecasts to score.
    static func reconstructed(_ data: Dataset, now: Date, months: Int = 18) -> [ForecastLogEntry] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        return (1...months).reversed().map { back in
            let asOf = cal.date(byAdding: .month, value: -back + 1, to: thisMonth)!
            let d = dataset(data, asOf: asOf)
            let fs = all(d, profiles: Analysis.profiles(d), asOf: asOf)
            return ForecastLogEntry(asOf: asOf, reconstructed: true,
                                    forecasts: Dictionary(uniqueKeysWithValues: fs.map { ($0.id, $0.snapshot) }))
        }
    }
}

/// Saved forecasts, one entry per day. The app keeps its own; the website's lives on the `data` branch.
enum ForecastLog {
    static func load(from url: URL) -> [ForecastLogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([ForecastLogEntry].self, from: data)) ?? []
    }

    /// Records today's forecasts, replacing any entry already saved today.
    static func record(_ forecasts: [Forecast], on day: Date = Date(), to url: URL) -> [ForecastLogEntry] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: day)
        var log = load(from: url).filter { !cal.isDate($0.asOf, inSameDayAs: today) }
        log.append(ForecastLogEntry(asOf: today, reconstructed: false,
                                    forecasts: Dictionary(uniqueKeysWithValues: forecasts.map { ($0.id, $0.snapshot) })))
        log.sort { $0.asOf < $1.asOf }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(log).write(to: url, options: .atomic)
        return log
    }
}
