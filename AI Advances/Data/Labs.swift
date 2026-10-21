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
        ("Google DeepMind", ["Google DeepMind", "Google", "Google Research", "Google Brain", "DeepMind"], ["Google"]),
        ("Meta", ["Meta AI", "Meta"], ["Meta", "Meta Llama", "meta-llama"]),
        ("xAI (SpaceXAI)", ["xAI", "SpaceXAI"], ["xAI", "SpaceXAI", "x-ai"]),
        ("Alibaba (Qwen)", ["Alibaba"], ["Qwen", "Alibaba"]),
        ("DeepSeek", ["DeepSeek"], ["DeepSeek"]),
        ("Moonshot AI", ["Moonshot"], ["MoonshotAI", "Moonshot AI"]),
        ("Z.ai", ["Z.ai (Zhipu AI)", "Zhipu AI"], ["Z.ai", "Z.AI", "z-ai"]),
        ("MiniMax", ["MiniMax"], ["MiniMax"]),
        ("Mistral AI", ["Mistral AI"], ["Mistral", "Mistral AI", "mistralai"]),
        ("NVIDIA", ["Nvidia", "NVIDIA"], ["NVIDIA"]),
        ("Thinking Machines", ["Thinking Machines"], ["Thinking Machines"]),
        ("ByteDance Seed", ["ByteDance", "ByteDance Seed"], ["ByteDance Seed", "ByteDance", "bytedance-seed"]),
    ]

    /// Spellings of untracked organizations that should read as one name.
    static let otherAliases: [String: String] = [
        "microsoft": "Microsoft", "microsoft research": "Microsoft", "salesforce research": "Salesforce",
        "xiaomi corp": "Xiaomi", "rekaai": "Reka AI", "reka": "Reka AI", "inclusionai": "inclusionAI",
        "cohere for ai": "Cohere", "ibm-granite": "IBM", "nousresearch": "Nous Research", "nous": "Nous Research",
    ]

    /// Model families whose lab Epoch sometimes leaves blank, keyed by `family(_:)`.
    static let curatedFamilies: [String: String] = [
        "qwen": "Alibaba (Qwen)", "codeqwen": "Alibaba (Qwen)", "granite": "IBM", "grok": "xAI (SpaceXAI)",
        "seed": "ByteDance Seed", "nemotron": "NVIDIA", "glm": "Z.ai", "chatglm": "Z.ai", "deepseek": "DeepSeek",
        "codex": "OpenAI", "gpt": "OpenAI", "c4ai": "Cohere", "command": "Cohere", "phi": "Microsoft",
        "palm": "Google DeepMind", "gemini": "Google DeepMind", "gemma": "Google DeepMind", "claude": "Anthropic",
        "llama": "Meta", "opt": "Meta", "mistral": "Mistral AI", "magistral": "Mistral AI", "devstral": "Mistral AI",
        "codestral": "Mistral AI", "yi": "01.AI", "baichuan": "Baichuan", "falcon": "Technology Innovation Institute",
        "kimi": "Moonshot AI", "minimax": "MiniMax", "mm": "Apple", "internlm": "Shanghai AI Laboratory",
        "internvl": "Shanghai AI Laboratory", "stablelm": "Stability AI", "instructblip": "Salesforce",
        "vicuna": "Large Model Systems Organization",
    ]

    /// Too generic to say whose model it is.
    private static let genericFamilies: Set<String> = ["tiny", "open", "computer", "model", "base", "chat", "the", "llava"]

    /// A model's family: its first word without version digits ("Qwen2.5-Coder-3B" -> "qwen",
    /// "chutes/GLM-4.5" -> "glm", "c4ai-command-r" -> "c4ai").
    static func family(_ name: String) -> String? {
        let f = families.value(name) { familyUncached($0) ?? "" }
        return f.isEmpty ? nil : f
    }

    private static func familyUncached(_ name: String) -> String? {
        let base = name.lowercased().split(separator: "/").last.map(String.init) ?? name.lowercased()
        if base.contains("llava") { return nil }   // academic models built on other labs' bases
        guard let first = base.split(whereSeparator: { " -_.".contains($0) }).first else { return nil }
        let f = String(first.reversed().drop { $0.isNumber }.reversed())
        guard f.count >= 2, f.first!.isLetter, !genericFamilies.contains(f) else { return nil }
        if f == "nvidia" { return "nemotron" }
        return f
    }

    /// The labs behind each family's known models.
    static func familyLabs(_ labs: [String: String]) -> [String: Set<String>] {
        var seen: [String: Set<String>] = [:]
        for (name, lab) in labs { if let f = family(name) { seen[f, default: []].insert(lab) } }
        return seen
    }

    /// The lab for a model with none given: its family's, when the family's known models all
    /// come from one lab (or, with none known, from the curated list); nil when it's unclear.
    static func inferredLab(_ name: String, families: [String: Set<String>]) -> String? {
        guard let f = family(name) else { return nil }
        if let known = families[f] { return known.count == 1 ? known.first : nil }
        return curatedFamilies[f]
    }

    private static let epochIndex: [String: String] = {
        var d: [String: String] = [:]
        for e in directory { for n in e.epoch { d[n.lowercased()] = e.name } }
        return d
    }()
    private static let openRouterIndex: [String: String] = {
        var d: [String: String] = [:]
        for e in directory { for n in e.openRouter { d[n.lowercased()] = e.name } }
        return d
    }()

    private static func firstOrg(_ org: String) -> String {
        (org.split(separator: ",", maxSplits: 1).first.map(String.init) ?? org).trimmingCharacters(in: .whitespaces)
    }

    static func lab(forEpoch org: String) -> String? {
        epochIndex[firstOrg(org).lowercased()]
    }

    static func lab(forOpenRouter name: String) -> String? {
        openRouterIndex[name.lowercased()]
    }

    /// The canonical lab for an Epoch organization (first listed), or its own name when it isn't
    /// a tracked lab. "Google" and "Google DeepMind" are one lab.
    private static let canonicalEpoch = KeyCache()
    private static let families = KeyCache()

    static func canonical(epoch org: String) -> String {
        canonicalEpoch.value(org) { org in
            let first = firstOrg(org)
            let k = first.lowercased()
            return epochIndex[k] ?? openRouterIndex[k] ?? otherAliases[k] ?? first
        }
    }

    /// The canonical lab for an OpenRouter provider name ("Google" -> "Google DeepMind").
    static func canonical(openRouter name: String) -> String {
        openRouterIndex[name.lowercased()] ?? epochIndex[name.lowercased()] ?? otherAliases[name.lowercased()] ?? name
    }

    /// A model's lab: the most common organization on its results; when Epoch gives none, the lab
    /// of its OpenRouter listing or of the matching notable model; "" only when nothing says.
    static func lab(ofRows orgs: [String], listing: ListedModel?, notable: NotableModel?) -> String {
        let counts = Dictionary(orgs.filter { !$0.isEmpty }.map { (canonical(epoch: $0), 1) }, uniquingKeysWith: +)
        if let best = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key, !best.isEmpty { return best }
        if let l = listing, !l.lab.isEmpty { return canonical(openRouter: l.lab) }
        if let n = notable, !n.organization.isEmpty { return canonical(epoch: n.organization) }
        return ""
    }

    static func summaries(_ data: Dataset, notes: [LabNote], now: Date) -> [LabSummary] {
        let yearAgo = now.addingTimeInterval(-365.25 * 86_400)
        let twoYearsAgo = now.addingTimeInterval(-2 * 365.25 * 86_400)
        let tracked = data.areas.flatMap { a in a.benchmarks.map { (benchmark: $0, area: a.name) } }

        // Each organization string resolved to a tracked lab once, not once per row.
        var epochLab: [String: String?] = [:]
        for org in Set(data.results.map(\.organization)) { epochLab[org] = Labs.lab(forEpoch: org) }
        var routerLab: [String: String?] = [:]
        for name in Set(data.listed.map(\.lab)) { routerLab[name] = Labs.lab(forOpenRouter: name) }
        let labOf = { (org: String) -> String? in epochLab[org] ?? Labs.lab(forEpoch: org) }
        let labOfListing = { (name: String) -> String? in routerLab[name] ?? Labs.lab(forOpenRouter: name) }
        let infos = Dictionary(data.benchmarks.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let inactive = Analysis.inactiveBenchmarks(data.results, now: now)

        // Overall best per benchmark, and each lab's best.
        var overall: [String: Double] = [:]
        var byLab: [String: [String: Double]] = [:]
        for r in data.results {
            overall[r.benchmark] = max(overall[r.benchmark] ?? 0, r.score)
            if let lab = labOf(r.organization) {
                byLab[lab, default: [:]][r.benchmark] = max(byLab[lab]?[r.benchmark] ?? 0, r.score)
            }
        }

        var held: [String: [String]] = [:]
        var recent: [String: [String: Int]] = [:]
        for t in tracked {
            let f = Analysis.frontier(data.results, benchmark: t.benchmark)
            // A record on a benchmark Epoch stopped updating isn't "held" any more.
            if !inactive.contains(t.benchmark), let top = f.last, let lab = labOf(top.organization) {
                held[lab, default: []].append(t.benchmark)
            }
            for p in f where Analysis.recordDate(p, released: infos[t.benchmark]?.releaseDate) >= yearAgo {
                if let lab = labOf(p.organization) { recent[lab, default: [:]][t.area, default: 0] += 1 }
            }
        }

        // First appearance of each model, from either source. Serving modes of one model
        // ("GPT-6 Sol" and "GPT-6 Sol Pro") count once, the same rule as the feed; a "Pro" with
        // no plain sibling (e.g. "Gemini 3 Pro") stays its own model.
        var labNames: [String: Set<String>] = [:]
        for r in data.results { if let lab = labOf(r.organization) { labNames[lab, default: []].insert(r.modelGroup) } }
        for m in data.listed { if let lab = labOfListing(m.lab) { labNames[lab, default: []].insert(m.name) } }
        var firstSeen: [String: [String: (name: String, date: Date)]] = [:]
        for r in data.results {
            guard let lab = labOf(r.organization) else { continue }
            let name = Feed.groupName(r.modelGroup, among: labNames[lab] ?? [])
            let key = Analysis.matchKey(name)
            if let seen = firstSeen[lab]?[key], seen.date <= r.releaseDate { continue }
            firstSeen[lab, default: [:]][key] = (name, r.releaseDate)
        }
        for m in data.listed {
            guard let lab = labOfListing(m.lab) else { continue }
            let name = Feed.groupName(m.name, among: labNames[lab] ?? [])
            let key = Analysis.matchKey(name)
            if let seen = firstSeen[lab]?[key], seen.date <= m.created { continue }
            firstSeen[lab, default: [:]][key] = (name, m.created)
        }

        return directory.map { entry in
            let lab = entry.name
            let models = (firstSeen[lab] ?? [:]).values.sorted { $0.date > $1.date }
            let quarters = Dictionary(grouping: models.filter { $0.date >= twoYearsAgo }) { Analysis.quarterStart($0.date) }
                .mapValues(\.count)

            var standing: [String: Double] = [:]
            for a in data.areas {
                // Only benchmarks the lab has a result on: a missing result is "not tested", not zero.
                // Both scores are measured from random chance, so guessing doesn't count as standing.
                let ratios = a.benchmarks.compactMap { b -> Double? in
                    guard let best = overall[b], let mine = byLab[lab]?[b] else { return nil }
                    let nb = Analysis.normalized(best, info: infos[b]), nm = Analysis.normalized(mine, info: infos[b])
                    guard nb > 0 else { return nil }
                    return min(1, nm / nb)
                }
                if !ratios.isEmpty { standing[a.name] = ratios.reduce(0, +) / Double(ratios.count) }
            }

            let listed = data.listed.filter { labOfListing($0.lab) == lab && $0.created >= yearAgo }
            var shares: [String: Double] = [:]
            if !listed.isEmpty {
                for m in Analysis.modalities {
                    let n = listed.filter { (m.output ? $0.outputModalities : $0.inputModalities).contains(m.key) }.count
                    shares[m.label] = Double(n) / Double(listed.count)
                }
            }
            let priced = data.listed.filter { labOfListing($0.lab) == lab && !$0.isFree }.map(\.blendedPrice)
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
