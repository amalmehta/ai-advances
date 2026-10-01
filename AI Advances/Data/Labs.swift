import Foundation

/// Researched notes on a lab's focus (bundled Labs.json; refreshed by re-running the research).
struct LabNote: Codable, Hashable {
    let name: String
    let focus: [String]
    let summary: String
    let bets: [String]
    let flagships: [String]
    let sources: [String]
    let asOf: String
}

struct LabSummary: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let note: LabNote?
    /// Lab's best score as a share of the overall best, averaged over each area's benchmarks.
    let standing: [String: Double]
    /// Benchmarks where the lab holds the current record.
    let recordsHeld: [String]
    /// Records the lab set in the last 12 months, by area.
    let recentRecords: [String: Int]
    let releasesByQuarter: [Date: Int]
    let recentModels: [String]
    let latest: (name: String, date: Date)?
    let modalityShare: [String: Double]
    let listedCount: Int
    let openShare: Double?
    let priceRange: ClosedRange<Double>?
    let largestRun: Double?

    static func == (a: LabSummary, b: LabSummary) -> Bool { a.name == b.name }
    func hash(into h: inout Hasher) { h.combine(name) }

    var pushingHardest: String? { recentRecords.max { $0.value < $1.value }?.key }
}

enum Labs {
    /// The labs tracked, with the names each source uses for them.
    static let directory: [(name: String, epoch: [String], openRouter: [String])] = [
        ("OpenAI", ["OpenAI"], ["OpenAI"]),
        ("Anthropic", ["Anthropic"], ["Anthropic"]),
        ("Google DeepMind", ["Google DeepMind", "Google", "Google Research", "Google Brain"], ["Google"]),
        ("Meta", ["Meta AI", "Meta"], ["Meta", "Meta Llama"]),
        ("xAI (SpaceXAI)", ["xAI", "SpaceXAI"], ["xAI", "SpaceXAI"]),
        ("Alibaba (Qwen)", ["Alibaba"], ["Qwen", "Alibaba"]),
        ("DeepSeek", ["DeepSeek"], ["DeepSeek"]),
        ("Moonshot AI", ["Moonshot"], ["MoonshotAI", "Moonshot AI"]),
        ("Z.ai", ["Z.ai (Zhipu AI)", "Zhipu AI"], ["Z.ai", "Z.AI"]),
        ("MiniMax", ["MiniMax"], ["MiniMax"]),
        ("Mistral AI", ["Mistral AI"], ["Mistral", "Mistral AI"]),
        ("NVIDIA", ["Nvidia", "NVIDIA"], ["NVIDIA"]),
        ("Thinking Machines", ["Thinking Machines"], ["Thinking Machines"]),
        ("ByteDance Seed", ["ByteDance", "ByteDance Seed"], ["ByteDance Seed", "ByteDance"]),
    ]

    static func lab(forEpoch org: String) -> String? {
        let first = org.components(separatedBy: ",").first ?? org
        return directory.first { $0.epoch.contains(first) }?.name
    }

    static func lab(forOpenRouter name: String) -> String? {
        directory.first { $0.openRouter.contains(name) }?.name
    }

    static func summaries(_ data: Dataset, notes: [LabNote], now: Date) -> [LabSummary] {
        let yearAgo = now.addingTimeInterval(-365.25 * 86_400)
        let twoYearsAgo = now.addingTimeInterval(-2 * 365.25 * 86_400)
        let tracked = data.areas.flatMap { a in a.benchmarks.map { (benchmark: $0, area: a.name) } }

        // Overall best per benchmark, and each lab's best.
        var overall: [String: Double] = [:]
        var byLab: [String: [String: Double]] = [:]
        for r in data.results {
            overall[r.benchmark] = max(overall[r.benchmark] ?? 0, r.score)
            if let lab = Labs.lab(forEpoch: r.organization) {
                byLab[lab, default: [:]][r.benchmark] = max(byLab[lab]?[r.benchmark] ?? 0, r.score)
            }
        }

        var held: [String: [String]] = [:]
        var recent: [String: [String: Int]] = [:]
        for t in tracked {
            let f = Analysis.frontier(data.results, benchmark: t.benchmark)
            if let top = f.last, let lab = Labs.lab(forEpoch: top.organization) { held[lab, default: []].append(t.benchmark) }
            for p in f where p.date >= yearAgo {
                if let lab = Labs.lab(forEpoch: p.organization) { recent[lab, default: [:]][t.area, default: 0] += 1 }
            }
        }

        // First appearance of each model, from either source.
        var firstSeen: [String: [String: (name: String, date: Date)]] = [:]
        for r in data.results {
            guard let lab = Labs.lab(forEpoch: r.organization) else { continue }
            let key = Analysis.matchKey(r.modelGroup)
            if let seen = firstSeen[lab]?[key], seen.date <= r.releaseDate { continue }
            firstSeen[lab, default: [:]][key] = (r.modelGroup, r.releaseDate)
        }
        for m in data.listed {
            guard let lab = Labs.lab(forOpenRouter: m.lab) else { continue }
            let key = Analysis.matchKey(m.name)
            if let seen = firstSeen[lab]?[key], seen.date <= m.created { continue }
            firstSeen[lab, default: [:]][key] = (m.name, m.created)
        }

        return directory.map { entry in
            let lab = entry.name
            let models = (firstSeen[lab] ?? [:]).values.sorted { $0.date > $1.date }
            let quarters = Dictionary(grouping: models.filter { $0.date >= twoYearsAgo }) { Analysis.quarterStart($0.date) }
                .mapValues(\.count)

            var standing: [String: Double] = [:]
            for a in data.areas {
                // Only benchmarks the lab has a result on: a missing result is "not tested", not zero.
                let ratios = a.benchmarks.compactMap { b -> Double? in
                    guard let best = overall[b], best > 0, let mine = byLab[lab]?[b] else { return nil }
                    return mine / best
                }
                if !ratios.isEmpty { standing[a.name] = ratios.reduce(0, +) / Double(ratios.count) }
            }

            let listed = data.listed.filter { Labs.lab(forOpenRouter: $0.lab) == lab && $0.created >= yearAgo }
            var shares: [String: Double] = [:]
            if !listed.isEmpty {
                for m in Analysis.modalities {
                    let n = listed.filter { (m.output ? $0.outputModalities : $0.inputModalities).contains(m.key) }.count
                    shares[m.label] = Double(n) / Double(listed.count)
                }
            }
            let priced = data.listed.filter { Labs.lab(forOpenRouter: $0.lab) == lab && !$0.isFree }.map(\.blendedPrice)
            let notable = data.notable.filter { m in m.date >= twoYearsAgo && entry.epoch.contains { m.organization.hasPrefix($0) } }
            let known = notable.compactMap(\.openWeights)

            return LabSummary(
                name: lab,
                note: notes.first { $0.name == lab },
                standing: standing,
                recordsHeld: held[lab] ?? [],
                recentRecords: recent[lab] ?? [:],
                releasesByQuarter: quarters,
                recentModels: models.filter { $0.date >= yearAgo }.map(\.name),
                latest: models.first,
                modalityShare: shares,
                listedCount: listed.count,
                openShare: known.isEmpty ? nil : Double(known.filter { $0 }.count) / Double(known.count),
                priceRange: priced.isEmpty ? nil : priced.min()!...priced.max()!,
                largestRun: data.notable.filter { m in entry.epoch.contains { m.organization.hasPrefix($0) } }.compactMap(\.computeFLOP).max())
        }
        .filter { $0.latest != nil }
    }
}
