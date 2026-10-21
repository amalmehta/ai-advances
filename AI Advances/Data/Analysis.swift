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
    /// Benchmarks left out because they're already past the saturation target: their last few
    /// points close a large share of a tiny gap and would make the area look fastest.
    var excludedReached: Int = 0
    /// Benchmarks left out because Epoch no longer adds results to them.
    var excludedInactive: Int = 0
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
    /// False when the listing was found by the loose name match (e.g. "DeepSeek-V4-Pro" to
    /// "DeepSeek V4 Pro 0423"); its date then says nothing about when this model was released.
    var listingIsExact: Bool = true

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
    /// The quarter isn't over yet.
    var partial: Bool = false
}

struct QuarterMedian: Identifiable, Hashable {
    var id: Date { quarterStart }
    let quarterStart: Date
    let median: Double
    let count: Int
    /// The quarter isn't over yet.
    let partial: Bool
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

    /// Successors Epoch's metadata doesn't (yet) record in `superseded_by`.
    static let curatedSuccessors: [String: String] = ["WeirdML": "WeirdML v3"]

    /// The benchmark that replaced `name`, following `superseded_by` (or the curated list) as
    /// long as the successor has results. Returns `name` when it hasn't been superseded.
    static func current(_ name: String, infos: [BenchmarkInfo], hasResults: Set<String>) -> String {
        var b = name
        var seen: Set<String> = [b]
        while let next = infos.first(where: { $0.name == b })?.supersededBy ?? curatedSuccessors[b],
              hasResults.contains(next), seen.insert(next).inserted {
            b = next
        }
        return b
    }

    /// `keyBenchmarks` with superseded benchmarks replaced by their successors (labels kept).
    static func keyBenchmarks(for data: Dataset) -> [(name: String, label: String)] {
        let has = Set(data.results.map(\.benchmark))
        return keyBenchmarks.map { (current($0.name, infos: data.benchmarks, hasResults: has), $0.label) }
    }

    static func followSupersession(_ areas: [CapabilityArea], data: Dataset) -> [CapabilityArea] {
        let has = Set(data.results.map(\.benchmark))
        return areas.map { a in
            var seen = Set<String>()
            let bs = a.benchmarks.map { current($0, infos: data.benchmarks, hasResults: has) }.filter { seen.insert($0).inserted }
            return CapabilityArea(name: a.name, summary: a.summary, benchmarks: bs)
        }
    }

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

    // MARK: Activity

    /// A benchmark with no result for a model released in the last 120 days is no longer being
    /// updated by Epoch (GDPval, VPCT, GeoBench and Terminal Bench in Oct 2026).
    static let inactiveAfterDays = 120.0

    static func lastResultDates(_ results: [BenchmarkResult]) -> [String: Date] {
        var last: [String: Date] = [:]
        for r in results where r.releaseDate > last[r.benchmark] ?? .distantPast { last[r.benchmark] = r.releaseDate }
        return last
    }

    static func inactiveBenchmarks(_ results: [BenchmarkResult], now: Date) -> Set<String> {
        let cutoff = now.addingTimeInterval(-inactiveAfterDays * 86_400)
        return Set(lastResultDates(results).filter { $0.value < cutoff }.keys)
    }

    /// A score as a share of the distance from random chance to the benchmark's ceiling, 0...1.
    static func normalized(_ s: Double, info: BenchmarkInfo?) -> Double {
        let base = info?.randomBaseline ?? 0, ceiling = info?.ceiling ?? 1
        guard ceiling > base else { return s }
        return max(0, min(1, (s - base) / (ceiling - base)))
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

    /// How much of each benchmark's remaining headroom the area closed over the window, averaged.
    /// Scores are measured from random chance to the ceiling. Benchmarks already past the
    /// saturation target, or no longer updated, are left out (and counted).
    static func momentum(area: CapabilityArea, results: [BenchmarkResult], infos: [BenchmarkInfo],
                         now: Date, months: Int = 12) -> AreaMomentum? {
        let start = Calendar.current.date(byAdding: .month, value: -months, to: now)!
        let inactive = inactiveBenchmarks(results.filter { area.benchmarks.contains($0.benchmark) }, now: now)
        var gaps: [Double] = []
        var gains: [Double] = []
        var reached = 0, stale = 0
        for b in area.benchmarks {
            let f = frontier(results, benchmark: b)
            guard let current = frontierValue(f, at: now) else { continue }
            if inactive.contains(b) { stale += 1; continue }
            let info = infos.first { $0.name == b }
            let ceiling = info?.ceiling ?? 1
            if current >= Forecasts.saturation * ceiling { reached += 1; continue }
            // A benchmark newer than the window starts from its first result.
            let base = frontierValue(f, at: start) ?? f.first!.score
            let n0 = normalized(base, info: info), n1 = normalized(current, info: info)
            guard n0 < 1 else { continue }
            gaps.append(max(0, min(1, (n1 - n0) / (1 - n0))))
            gains.append((current - base) * 100)
        }
        guard !gaps.isEmpty else { return nil }
        return AreaMomentum(area: area.name,
                            gapClosed: gaps.reduce(0, +) / Double(gaps.count),
                            pointsGained: gains.reduce(0, +) / Double(gains.count),
                            benchmarksUsed: gaps.count, excludedReached: reached, excludedInactive: stale)
    }

    // MARK: Model profiles

    /// Words that label a listing rather than name a different model. The precise key drops only
    /// the first set; the loose key, used when there's no exact match, drops them all.
    static let fillerWords: Set<String> = ["latest", "it"]
    static let looseFillerWords: Set<String> = ["latest", "it", "preview", "experimental", "exp", "beta", "instruct", "fp8"]
    /// Lab names that some sources put in front of the model name ("Tencent Hy4 preview").
    static let labPrefixes: Set<String> = ["tencent", "google", "meta", "microsoft", "ibm", "nvidia", "amazon",
                                           "baidu", "openai", "anthropic", "xai", "cohere", "mistralai", "bytedance"]

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9,
        "oct": 10, "nov": 11, "dec": 12, "january": 1, "february": 2, "march": 3, "april": 4, "june": 6,
        "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
    ]
    private static let isoDate = try! NSRegularExpression(pattern: #"\b((?:19|20)\d{2})-(\d{2})-\d{2}\b"#)
    private static let monthYear = try! NSRegularExpression(pattern: #"\b([a-z]{3,9})\.?\s+((?:19|20)\d{2})\b"#)

    /// The year and month a name carries, as "yyyymm": "GPT-4o (Aug 2024)" and "GPT-4o (2024-08-06)"
    /// both give "202408".
    static func monthStamp(_ lowercased: String) -> (String, Range<String.Index>)? {
        let ns = lowercased as NSString
        let all = NSRange(location: 0, length: ns.length)
        if let m = isoDate.firstMatch(in: lowercased, range: all), let r = Range(m.range, in: lowercased) {
            return (ns.substring(with: m.range(at: 1)) + ns.substring(with: m.range(at: 2)), r)
        }
        for m in monthYear.matches(in: lowercased, range: all) {
            guard let month = monthNumbers[ns.substring(with: m.range(at: 1))], let r = Range(m.range, in: lowercased) else { continue }
            return (ns.substring(with: m.range(at: 2)) + String(format: "%02d", month), r)
        }
        return nil
    }

    private static func key(_ name: String, loose: Bool) -> String {
        var s = name.lowercased()
        if let r = s.range(of: ":") { s = String(s[r.upperBound...]) }              // "Lab: Model"
        if let r = s.range(of: "/", options: .backwards) { s = String(s[r.upperBound...]) }  // "chutes/GLM-4.5"
        // Dates become one "yyyymm" token (precise) or go (loose).
        while let (stamp, r) = monthStamp(s) { s.replaceSubrange(r, with: loose ? " " : " \(stamp) ") }
        if loose {
            // Parenthetical notes ("hosted 397B-A17B") go too; the precise key keeps them.
            s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        }
        var words: [String] = []
        for raw in s.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "+") }) {
            // Keep "." only between digits: "1.5b" isn't "15b", "gpt-6.1" isn't "gpt-61".
            let cs = Array(raw)
            var w = ""
            for (i, c) in cs.enumerated() where c != "." || (i > 0 && i + 1 < cs.count && cs[i - 1].isNumber && cs[i + 1].isNumber) {
                w.append(c)
            }
            guard !w.isEmpty, !(loose ? looseFillerWords : fillerWords).contains(w) else { continue }
            // Trailing-style snapshot stamps ("0423", "2512") and month tokens only in the precise key.
            if loose && w.allSatisfy(\.isNumber) && (w.count == 4 || w.count == 6) && !words.isEmpty { continue }
            words.append(w)
        }
        if words.count > 1, labPrefixes.contains(words[0]) { words.removeFirst() }
        return words.joined()
    }

    private static let preciseKeys = KeyCache()
    private static let looseKeys = KeyCache()

    /// Name key that joins one model across sources: "Claude Opus 5.5" (Epoch) and "Anthropic:
    /// Claude Opus 5.5" (OpenRouter). Keeps sizes and dates ("Qwen2.5-Coder (1.5B)" vs "(7B)",
    /// "GPT-4o (Aug 2024)" vs "(May 2024)"), "+" and "." between digits, preview/exp/instruct and
    /// snapshot stamps; drops lab and host prefixes. Memoized.
    static func matchKey(_ name: String) -> String { preciseKeys.value(name) { key($0, loose: false) } }

    /// Looser key for when nothing matches exactly: also drops parenthetical notes, dates,
    /// snapshot stamps and preview/beta/instruct labels, so "Gemini 3.1 Pro" finds
    /// "Gemini 3.1 Pro Preview" when that's the only listing.
    static func looseKey(_ name: String) -> String { looseKeys.value(name) { key($0, loose: true) } }

    /// Links each name in `names` to at most one item: an exact `matchKey` match first; otherwise a
    /// `looseKey` match that's unambiguous (one unmatched name with that loose key), or, when
    /// several names share it, the one whose own date is within about a month of the item's.
    static func link<T>(_ names: [String], to items: [T], name: (T) -> String, date: (T) -> Date) -> [String: (item: T, exact: Bool)] {
        let order = items.indices.sorted { date(items[$0]) < date(items[$1]) }
        var exact: [String: Int] = [:]
        var loose: [String: [Int]] = [:]
        for i in order {
            let n = name(items[i])
            if exact[matchKey(n)] == nil { exact[matchKey(n)] = i }
            loose[looseKey(n), default: []].append(i)
        }
        var out: [String: (item: T, exact: Bool)] = [:]
        var claimed = Set<Int>()
        let unique = Array(Set(names))
        for n in unique { if let i = exact[matchKey(n)] { out[n] = (items[i], true); claimed.insert(i) } }
        let rest = Dictionary(grouping: unique.filter { out[$0] == nil }, by: looseKey)
        for (lk, group) in rest {
            let candidates = (loose[lk] ?? []).filter { !claimed.contains($0) }
            guard !candidates.isEmpty else { continue }
            if group.count == 1 {
                out[group[0]] = (items[candidates[0]], false)
                claimed.insert(candidates[0])
                continue
            }
            // Several dated names ("Gemini 2.5 Flash (May 2025)", "(Jun 2025)"): the item goes to the
            // one dated nearest its own date, if that's within about a month and clearly nearest.
            let dated = group.compactMap { n -> (String, Date)? in
                guard let stamp = monthStamp(n.lowercased())?.0,
                      let when = Dates.parse(String(stamp.prefix(4)) + "-" + String(stamp.suffix(2)) + "-15") else { return nil }
                return (n, when)
            }
            for i in candidates {
                let d = date(items[i])
                let byDistance = dated.filter { out[$0.0] == nil }
                    .map { ($0.0, abs($0.1.timeIntervalSince(d))) }.sorted { $0.1 < $1.1 }
                guard let best = byDistance.first, best.1 < 46 * 86_400,
                      byDistance.count == 1 || byDistance[1].1 > best.1 + 7 * 86_400 else { continue }
                out[best.0] = (items[i], false)
                claimed.insert(i)
            }
        }
        return out
    }

    static func profiles(_ data: Dataset) -> [ModelProfile] {
        let byGroup = Dictionary(grouping: data.results, by: \.modelGroup)
        let groups = Array(byGroup.keys)
        let listings = link(groups, to: data.listed, name: \.name, date: \.created)
        let notable = link(groups, to: data.notable, name: \.name, date: \.date)
        var horizons: [String: Double] = [:]
        for h in data.horizons { horizons[h.modelGroup] = max(horizons[h.modelGroup] ?? 0, h.minutes) }

        var labs: [String: String] = [:]
        for (group, rows) in byGroup {
            labs[group] = Labs.lab(ofRows: rows.map(\.organization), listing: listings[group]?.item, notable: notable[group]?.item)
        }
        // Still unknown: take the lab of the model's family ("granite-4.0-1b" -> IBM).
        let families = Labs.familyLabs(labs.filter { !$0.value.isEmpty })
        for (group, lab) in labs where lab.isEmpty {
            if let l = Labs.inferredLab(group, families: families) { labs[group] = l }
        }

        return byGroup.map { group, rows in
            var scores: [String: Double] = [:]
            for r in rows { scores[r.benchmark] = max(scores[r.benchmark] ?? 0, r.score) }
            let listing = listings[group]
            let n = notable[group]?.item
            return ModelProfile(
                name: group,
                lab: labs[group] ?? "",
                released: rows.map(\.releaseDate).min()!,
                scores: scores,
                horizonMinutes: horizons[group],
                listing: listing?.item,
                computeFLOP: n?.computeFLOP,
                openWeights: n?.openWeights,
                listingIsExact: listing?.exact ?? true)
        }
        .sorted { $0.released > $1.released }
    }

    // MARK: Cost

    /// Cheapest listed price for a model scoring at least `threshold` on `benchmark`, as it fell over time.
    static func cheapestOverTime(_ profiles: [ModelProfile], benchmark: String, threshold: Double) -> [PriceStep] {
        let candidates = profiles.compactMap { p -> PriceStep? in
            guard let s = p.score(benchmark), s >= threshold, let l = p.listing, !l.isFree else { return nil }
            // A loosely matched listing may be a different snapshot: don't let it backdate the step.
            return PriceStep(date: p.listingIsExact ? min(p.released, l.created) : p.released,
                             price: l.blendedPrice, model: p.name, score: s)
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

    /// Quarters with fewer models than this are left out: a share of 3 models says little.
    static let minModelsPerQuarter = 8

    static func quarterIsPartial(_ start: Date, now: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(byAdding: .month, value: 3, to: start)! > now
    }

    /// Share of models first listed in each quarter that support each modality. The current
    /// quarter is marked `partial`; quarters with too few models are dropped.
    static func modalityShares(_ listed: [ListedModel], since: Date, now: Date = Date()) -> [QuarterShare] {
        let byQuarter = Dictionary(grouping: listed.filter { $0.created >= since }) { quarterStart($0.created) }
            .filter { $0.value.count >= minModelsPerQuarter }
        return byQuarter.keys.sorted().flatMap { q -> [QuarterShare] in
            let models = byQuarter[q]!
            return modalities.map { m in
                let hits = models.filter { (m.output ? $0.outputModalities : $0.inputModalities).contains(m.key) }.count
                return QuarterShare(quarter: quarterLabel(q), quarterStart: q, modality: m.label,
                                    share: Double(hits) / Double(models.count), count: models.count,
                                    partial: quarterIsPartial(q, now: now))
            }
        }
    }

    static func contextMedians(_ listed: [ListedModel], since: Date, now: Date = Date()) -> [QuarterMedian] {
        let byQuarter = Dictionary(grouping: listed.filter { $0.created >= since && $0.contextLength > 0 }) { quarterStart($0.created) }
            .filter { $0.value.count >= minModelsPerQuarter }
        return byQuarter.keys.sorted().map { q in
            let v = byQuarter[q]!.map { Double($0.contextLength) }.sorted()
            let mid = v.count / 2
            return QuarterMedian(quarterStart: q, median: v.count % 2 == 0 ? (v[mid - 1] + v[mid]) / 2 : v[mid],
                                 count: v.count, partial: quarterIsPartial(q, now: now))
        }
    }

    static func medianContextByQuarter(_ listed: [ListedModel], since: Date, now: Date = Date()) -> [(Date, Double)] {
        contextMedians(listed, since: since, now: now).map { ($0.quarterStart, $0.median) }
    }

    // MARK: Compute & horizons

    /// Training runs that were the largest known when they were published (the running maximum),
    /// from `since` on. Epoch's own "frontier" flag lags new releases, so it isn't used.
    static func computeRecords(_ notable: [NotableModel], since: Date) -> [NotableModel] {
        var best = 0.0
        return notable.filter { $0.computeFLOP != nil }.sorted { $0.date < $1.date }.filter {
            guard $0.computeFLOP! > best else { return false }
            best = $0.computeFLOP!
            return true
        }
        .filter { $0.date >= since }
    }

    static func computeFit(_ notable: [NotableModel], since: Date) -> ExpFit? {
        ExpFit.fit(computeRecords(notable, since: since).map { ($0.date, $0.computeFLOP!) })
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

    /// METR's longest tasks run to roughly 16 hours; a horizon past that, or one where the model
    /// solved 85% or more of the suite, is the top of what the suite can measure, so the real
    /// value is at least this.
    static let metrSuiteTopMinutes = 16.0 * 60

    static func horizonIsLowerBound(_ h: TimeHorizon) -> Bool {
        h.minutes >= metrSuiteTopMinutes || (h.averageScore ?? 0) >= 0.85
    }

    // MARK: Generated advances

    struct Record: Identifiable, Hashable {
        var id: String { point.id }
        let point: FrontierPoint
        let previous: Double?
        /// When the record became public: no earlier than the benchmark itself.
        let date: Date
    }

    /// A record's date: the model's release, or the benchmark's if that came later.
    static func recordDate(_ p: FrontierPoint, released: Date?) -> Date { max(p.date, released ?? p.date) }

    /// New state-of-the-art results on the tracked benchmarks since `since`, newest first.
    /// With `now`, benchmarks Epoch no longer updates are left out.
    static func recentRecords(_ data: Dataset, since: Date, now: Date? = nil) -> [Record] {
        let inactive = now.map { inactiveBenchmarks(data.results, now: $0) } ?? []
        let tracked = Set(data.areas.flatMap(\.benchmarks)).subtracting(inactive)
        let released = Dictionary(data.benchmarks.map { ($0.name, $0.releaseDate) }, uniquingKeysWith: { a, _ in a })
        return tracked.flatMap { b -> [Record] in
            let f = frontier(data.results, benchmark: b)
            return f.enumerated().compactMap { i, p in
                let d = recordDate(p, released: released[b] ?? nil)
                return d >= since && i > 0 ? Record(point: p, previous: f[i - 1].score, date: d) : nil
            }
        }
        .sorted { $0.date > $1.date }
    }
}

/// Thread-safe memo for pure String -> String functions (name keys are asked for repeatedly).
final class KeyCache: @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    func value(_ k: String, _ make: (String) -> String) -> String {
        lock.lock()
        if let v = store[k] { lock.unlock(); return v }
        lock.unlock()
        let v = make(k)
        lock.lock()
        store[k] = v
        lock.unlock()
        return v
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
