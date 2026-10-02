import Foundation

struct FrontierPoint: Hashable, Identifiable {
    var id: String { benchmark + model + "\(date.timeIntervalSince1970)" }
    let benchmark: String
    let date: Date
    let score: Double
    let model: String
    let organization: String
}

/// Least-squares fit of log10(y) against time, for exponential trends.
struct ExpFit: Hashable {
    let slope: Double      // log10 units per year
    let intercept: Double
    let n: Int

    /// Months for y to double (negative when y is falling).
    var doublingMonths: Double { 12 * log10(2) / slope }
    /// Multiplier per year, e.g. 4.1 = "4.1× per year", 0.1 = "falls 10× per year".
    var factorPerYear: Double { pow(10, slope) }

    func value(at date: Date) -> Double { pow(10, intercept + slope * Dates.years(date)) }

    static func fit(_ points: [(Date, Double)]) -> ExpFit? {
        let pts = points.filter { $0.1 > 0 }.map { (Dates.years($0.0), log10($0.1)) }
        guard pts.count >= 3 else { return nil }
        let n = Double(pts.count)
        let mx = pts.map(\.0).reduce(0, +) / n
        let my = pts.map(\.1).reduce(0, +) / n
        let sxx = pts.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let sxy = pts.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +)
        let slope = sxy / sxx
        return ExpFit(slope: slope, intercept: my - slope * mx, n: pts.count)
    }
}

struct AreaMomentum: Identifiable, Hashable {
    var id: String { area }
    let area: String
    /// Share of the remaining headroom (to each benchmark's ceiling) closed over the window, averaged across benchmarks.
    let gapClosed: Double
    /// Average absolute gain in percentage points.
    let pointsGained: Double
    let benchmarksUsed: Int
}

struct ModelProfile: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let lab: String
    let released: Date
    /// Best score across reasoning-effort variants, 0...1, keyed by benchmark name.
    let scores: [String: Double]
    let horizonMinutes: Double?
    let listing: ListedModel?
    let computeFLOP: Double?
    let openWeights: Bool?

    func score(_ benchmark: String) -> Double? { scores[benchmark] }
}

struct PriceStep: Identifiable, Hashable {
    var id: String { model + "\(date.timeIntervalSince1970)" }
    let date: Date
    let price: Double
    let model: String
    let score: Double
}

struct QuarterShare: Identifiable, Hashable {
    var id: String { quarter + modality }
    let quarter: String
    let quarterStart: Date
    let modality: String
    let share: Double
    let count: Int
}

enum Analysis {
    /// The benchmarks shown as columns in the Models table, with short labels.
    static let keyBenchmarks: [(name: String, label: String)] = [
        ("GPQA diamond", "GPQA"),
        ("SimpleQA Verified", "SimpleQA"),
        ("FrontierMath-Tiers-1-3-v2-Private", "FrontierMath"),
        ("ARC-AGI-2", "ARC-AGI-2"),
        ("FrontierCode", "FrontierCode"),
        ("WeirdML", "WeirdML"),
        ("APEX-Agents", "APEX-Agents"),
    ]

    static let otherShortNames = [
        "FrontierMath-Tier-4-v2-Private": "FrontierMath T4",
        "SWE-Bench verified": "SWE-bench",
        "Terminal Bench": "Terminal-Bench",
        "OSWorld 2.0": "OSWorld 2",
    ]

    static func shortName(_ benchmark: String) -> String {
        keyBenchmarks.first { $0.name == benchmark }?.label
            ?? otherShortNames[benchmark]
            ?? benchmark.replacingOccurrences(of: "-Private", with: "")
    }

    // MARK: Frontier

    /// The record-setting results for one benchmark, oldest first.
    static func frontier(_ results: [BenchmarkResult], benchmark: String) -> [FrontierPoint] {
        let rows = results.filter { $0.benchmark == benchmark }
            .sorted { $0.releaseDate == $1.releaseDate ? $0.score > $1.score : $0.releaseDate < $1.releaseDate }
        var best = -Double.infinity
        var out: [FrontierPoint] = []
        for r in rows where r.score > best + 1e-9 {
            best = r.score
            out.append(FrontierPoint(benchmark: benchmark, date: r.releaseDate, score: r.score,
                                     model: r.modelGroup, organization: r.organization))
        }
        return out
    }

    static func frontierValue(_ frontier: [FrontierPoint], at date: Date) -> Double? {
        frontier.last { $0.date <= date }?.score
    }

    static func momentum(area: CapabilityArea, results: [BenchmarkResult], infos: [BenchmarkInfo],
                         now: Date, months: Int = 12) -> AreaMomentum? {
        let start = Calendar.current.date(byAdding: .month, value: -months, to: now)!
        var gaps: [Double] = []
        var gains: [Double] = []
        for b in area.benchmarks {
            let f = frontier(results, benchmark: b)
            guard let current = frontierValue(f, at: now) else { continue }
            // A benchmark newer than the window starts from its first result.
            let base = frontierValue(f, at: start) ?? f.first!.score
            let ceiling = infos.first { $0.name == b }?.ceiling ?? 1
            guard ceiling > base else { continue }
            gaps.append(max(0, min(1, (current - base) / (ceiling - base))))
            gains.append((current - base) * 100)
        }
        guard !gaps.isEmpty else { return nil }
        return AreaMomentum(area: area.name,
                            gapClosed: gaps.reduce(0, +) / Double(gaps.count),
                            pointsGained: gains.reduce(0, +) / Double(gains.count),
                            benchmarksUsed: gaps.count)
    }

    // MARK: Model profiles

    /// Loose name key so "Claude Opus 5.5" (Epoch) matches "Anthropic: Claude Opus 5.5" (OpenRouter).
    /// Words that label a listing rather than name a different model.
    static let fillerWords: Set<String> = ["preview", "latest", "experimental", "exp", "beta", "it", "instruct"]

    static func matchKey(_ name: String) -> String {
        var s = name.lowercased()
        if let r = s.range(of: ":") { s = String(s[r.upperBound...]) }
        if let r = s.range(of: "(") { s = String(s[..<r.lowerBound]) }
        // Snapshot dates: "2026-02-15" anywhere, or a trailing-style 4-digit stamp such as "0423" or "2512".
        s = s.replacingOccurrences(of: #"\b(19|20)\d{2}-\d{2}-\d{2}\b"#, with: " ", options: .regularExpression)
        let words = s.split { !($0.isLetter || $0.isNumber || $0 == ".") }
            .map(String.init)
            .filter { w in !fillerWords.contains(w) && !(w.count == 4 && w.allSatisfy(\.isNumber)) }
        return words.joined().filter { $0.isLetter || $0.isNumber }
    }

    static func profiles(_ data: Dataset) -> [ModelProfile] {
        var listings: [String: ListedModel] = [:]
        for m in data.listed.sorted(by: { $0.created < $1.created }) where listings[matchKey(m.name)] == nil {
            listings[matchKey(m.name)] = m
        }
        var notable: [String: NotableModel] = [:]
        for m in data.notable { notable[matchKey(m.name)] = m }
        var horizons: [String: Double] = [:]
        for h in data.horizons { horizons[h.modelGroup] = max(horizons[h.modelGroup] ?? 0, h.minutes) }

        let byGroup = Dictionary(grouping: data.results, by: \.modelGroup)
        return byGroup.map { group, rows in
            var scores: [String: Double] = [:]
            for r in rows { scores[r.benchmark] = max(scores[r.benchmark] ?? 0, r.score) }
            let key = matchKey(group)
            let n = notable[key]
            return ModelProfile(
                name: group,
                lab: rows.first?.organization.components(separatedBy: ",").first ?? "",
                released: rows.map(\.releaseDate).min()!,
                scores: scores,
                horizonMinutes: horizons[group],
                listing: listings[key],
                computeFLOP: n?.computeFLOP,
                openWeights: n?.openWeights)
        }
        .sorted { $0.released > $1.released }
    }

    // MARK: Cost

    /// Cheapest listed price for a model scoring at least `threshold` on `benchmark`, as it fell over time.
    static func cheapestOverTime(_ profiles: [ModelProfile], benchmark: String, threshold: Double) -> [PriceStep] {
        let candidates = profiles.compactMap { p -> PriceStep? in
            guard let s = p.score(benchmark), s >= threshold, let l = p.listing, !l.isFree else { return nil }
            return PriceStep(date: min(p.released, l.created), price: l.blendedPrice, model: p.name, score: s)
        }
        .sorted { $0.date < $1.date }
        var best = Double.infinity
        var out: [PriceStep] = []
        for c in candidates where c.price < best {
            best = c.price
            out.append(c)
        }
        return out
    }

    // MARK: Context & modalities

    static func contextFrontier(_ listed: [ListedModel]) -> [ListedModel] {
        var best = 0
        return listed.sorted { $0.created < $1.created }.filter {
            guard $0.contextLength > best else { return false }
            best = $0.contextLength
            return true
        }
    }

    static func quarterStart(_ d: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month], from: d)
        let q = ((c.month! - 1) / 3) * 3 + 1
        return cal.date(from: DateComponents(year: c.year, month: q, day: 1))!
    }

    static func quarterLabel(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month], from: d)
        return "Q\((c.month! - 1) / 3 + 1) \(c.year!)"
    }

    static let modalities: [(key: String, label: String, output: Bool)] = [
        ("image", "Image input", false),
        ("file", "File input", false),
        ("audio", "Audio input", false),
        ("video", "Video input", false),
        ("image", "Image output", true),
    ]

    /// Share of models first listed in each quarter that support each modality.
    static func modalityShares(_ listed: [ListedModel], since: Date) -> [QuarterShare] {
        let byQuarter = Dictionary(grouping: listed.filter { $0.created >= since }) { quarterStart($0.created) }
        return byQuarter.keys.sorted().flatMap { q -> [QuarterShare] in
            let models = byQuarter[q]!
            return modalities.map { m in
                let hits = models.filter { (m.output ? $0.outputModalities : $0.inputModalities).contains(m.key) }.count
                return QuarterShare(quarter: quarterLabel(q), quarterStart: q, modality: m.label,
                                    share: Double(hits) / Double(models.count), count: models.count)
            }
        }
    }

    static func medianContextByQuarter(_ listed: [ListedModel], since: Date) -> [(Date, Double)] {
        let byQuarter = Dictionary(grouping: listed.filter { $0.created >= since && $0.contextLength > 0 }) { quarterStart($0.created) }
        return byQuarter.keys.sorted().map { q in
            let v = byQuarter[q]!.map { Double($0.contextLength) }.sorted()
            let mid = v.count / 2
            return (q, v.count % 2 == 0 ? (v[mid - 1] + v[mid]) / 2 : v[mid])
        }
    }

    // MARK: Compute & horizons

    static func computeFit(_ notable: [NotableModel], since: Date) -> ExpFit? {
        ExpFit.fit(notable.filter { $0.isFrontier && $0.date >= since }.compactMap { m in m.computeFLOP.map { (m.date, $0) } })
    }

    /// Running-maximum METR horizons, oldest first.
    static func horizonFrontier(_ horizons: [TimeHorizon]) -> [TimeHorizon] {
        var best = 0.0
        return horizons.sorted { $0.releaseDate < $1.releaseDate }.filter {
            guard $0.minutes > best else { return false }
            best = $0.minutes
            return true
        }
    }

    // MARK: Generated advances

    struct Record: Identifiable, Hashable {
        var id: String { point.id }
        let point: FrontierPoint
        let previous: Double?
    }

    /// New state-of-the-art results on the tracked benchmarks since `since`, newest first.
    static func recentRecords(_ data: Dataset, since: Date) -> [Record] {
        let tracked = Set(data.areas.flatMap(\.benchmarks))
        return tracked.flatMap { b -> [Record] in
            let f = frontier(data.results, benchmark: b)
            return f.enumerated().compactMap { i, p in
                p.date >= since && i > 0 ? Record(point: p, previous: f[i - 1].score) : nil
            }
        }
        .sorted { $0.point.date > $1.point.date }
    }
}

enum Format {
    static func percent(_ v: Double?, digits: Int = 0) -> String {
        guard let v else { return "–" }
        return String(format: "%.\(digits)f%%", v * 100)
    }

    static func price(_ v: Double) -> String {
        v >= 10 ? String(format: "$%.0f", v) : v >= 1 ? String(format: "$%.2f", v) : String(format: "$%.3f", v)
    }

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: n % 1_000_000 == 0 ? "%.0fM" : "%.2gM", Double(n) / 1e6)
            : n >= 1000 ? "\(n / 1000)K" : "\(n)"
    }

    static func flop(_ v: Double) -> String {
        let e = Int(floor(log10(v)))
        return String(format: "%.1f × 10^%d", v / pow(10, Double(e)), e)
    }

    static func minutes(_ m: Double) -> String {
        m < 60 ? String(format: "%.0f min", m) : m < 60 * 24 ? String(format: "%.1f hours", m / 60) : String(format: "%.1f days", m / 1440)
    }

    static func months(_ m: Double) -> String { String(format: "%.1f months", m) }

    static func monthYear(_ d: Date) -> String { monthYearFormatter.string(from: d) }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
