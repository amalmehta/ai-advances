import Foundation

/// The Latest Advances feed: researched highlights, new benchmark records and new model listings.
struct FeedItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Codable { case curated = "Highlights", records = "New records", models = "New models" }

    let id: String
    let date: Date
    let title: String
    let detail: String
    let lab: String
    let kind: Kind
    let direction: String
    let link: String?
}

enum Feed {
    /// Trailing words that name a serving mode of the same model rather than a different model:
    /// "GPT-6.1 Sol Pro" is GPT-6.1 Sol run with more reasoning. "Flash" or "Mini" are different models.
    static let variantWords: Set<String> = ["pro", "prime", "contributor"]

    /// The model a listing is a variant of: "GPT-6.1 Sol Pro" -> "GPT-6.1 Sol".
    static func baseName(_ name: String) -> String {
        var words = name.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, variantWords.contains(last.lowercased()) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// One feed item per model per day: a base model and its variants listed the same day merge.
    static func modelListings(_ listed: [ListedModel]) -> [FeedItem] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let groups = Dictionary(grouping: listed) { m in
            "\(m.lab)|\(baseName(m.name))|\(cal.startOfDay(for: m.created).timeIntervalSince1970)"
        }
        return groups.values.map { group in
            let sorted = group.sorted { $0.name.count < $1.name.count }   // the base listing first
            let m = sorted[0]
            let base = baseName(m.name)
            let variants = sorted.map(\.name).filter { $0 != base }
            let also = variants.isEmpty ? "" : " (also as " + variants.map { String($0.dropFirst(base.count)).trimmingCharacters(in: .whitespaces) }.joined(separator: ", ") + ")"
            return FeedItem(id: "m" + m.id, date: group.map(\.created).min()!, title: "\(m.lab) lists \(base)\(also)",
                            detail: "\(Format.tokens(m.contextLength)) context · \(m.isFree ? "free" : Format.price(m.blendedPrice) + " / M tokens") · takes \(m.inputModalities.sorted().joined(separator: ", "))",
                            lab: m.lab, kind: .models, direction: "New models",
                            link: "https://openrouter.ai/\(m.id)")
        }
    }

    static let areaDirection: [String: String] = [
        "Reasoning & knowledge": "Reasoning", "Math": "Reasoning", "Novel problem solving": "Reasoning",
        "Coding": "Coding", "Agents & real work": "Agents", "Vision & spatial": "Multimodal",
    ]

    static func items(_ data: Dataset, now: Date) -> [FeedItem] {
        let yearAgo = now.addingTimeInterval(-365.25 * 86_400)
        let curated = data.advances.map {
            FeedItem(id: "c" + $0.id, date: $0.day, title: $0.title, detail: $0.summary, lab: $0.lab,
                     kind: .curated, direction: $0.direction, link: $0.source)
        }
        let areaOf = Dictionary(data.areas.flatMap { a in a.benchmarks.map { ($0, a.name) } }, uniquingKeysWith: { a, _ in a })
        let records = Analysis.recentRecords(data, since: yearAgo).map { r in
            FeedItem(id: "r" + r.id, date: r.point.date,
                     title: "\(r.point.model) sets a \(Analysis.shortName(r.point.benchmark)) record",
                     detail: "\(Format.percent(r.point.score, digits: 1)), up from \(Format.percent(r.previous, digits: 1)). \(areaOf[r.point.benchmark] ?? "") benchmark.",
                     lab: r.point.organization, kind: .records,
                     direction: areaDirection[areaOf[r.point.benchmark] ?? ""] ?? "Reasoning",
                     link: "https://epoch.ai/benchmarks")
        }
        let models = modelListings(data.listed.filter { $0.created >= now.addingTimeInterval(-60 * 86_400) })
        return (curated + records + models).sorted { $0.date > $1.date }
    }
}
