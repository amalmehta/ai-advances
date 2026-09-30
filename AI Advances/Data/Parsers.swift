import Foundation

enum ParseError: LocalizedError {
    case missing(String)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .missing(let f): return "Missing file: \(f)"
        case .empty(let f): return "No usable rows in \(f)"
        }
    }
}

enum EpochParser {
    /// Parses the unzipped `benchmark_data.zip` folder.
    static func benchmarks(in dir: URL) throws -> (infos: [BenchmarkInfo], results: [BenchmarkResult], horizons: [TimeHorizon]) {
        let metaURL = dir.appendingPathComponent("benchmark_metadata.csv")
        guard let metaText = try? String(contentsOf: metaURL, encoding: .utf8) else { throw ParseError.missing("benchmark_metadata.csv") }

        var groups: [String: (group: String, org: String)] = [:]
        if let text = try? String(contentsOf: dir.appendingPathComponent("model_metadata.csv"), encoding: .utf8) {
            for r in CSV.records(text) {
                guard let v = r["model_version"], !v.isEmpty, let g = r["model_group"], !g.isEmpty else { continue }
                groups[v] = (g, r["organization"] ?? "")
            }
        }

        var infos: [BenchmarkInfo] = []
        var results: [BenchmarkResult] = []
        var horizons: [TimeHorizon] = []

        for m in CSV.records(metaText) {
            guard let name = m["benchmark"], let file = m["source_file"], !file.isEmpty,
                  let column = m["score_column"], !column.isEmpty else { continue }
            let info = BenchmarkInfo(
                name: name, sourceFile: file, scoreColumn: column,
                scale: Double(m["scale"] ?? "") ?? 1,
                randomBaseline: Double(m["random_baseline"] ?? "") ?? 0,
                ceiling: Double(m["score_ceiling"] ?? "") ?? 1,
                releaseDate: Dates.parse(m["release_date"]),
                supersededBy: (m["superseded_by"]?.isEmpty ?? true) ? nil : m["superseded_by"])
            guard let text = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else { continue }
            infos.append(info)

            for r in CSV.records(text) {
                guard let version = r["Model version"], !version.isEmpty,
                      let date = Dates.parse(r["Release date"]) else { continue }
                let meta = groups[version]
                let group = meta?.group ?? prettyGroup(version)
                let org = (r["Organization"]?.isEmpty == false ? r["Organization"]! : meta?.org) ?? ""
                if let raw = Double(r[column] ?? "") {
                    results.append(BenchmarkResult(benchmark: name, modelVersion: version, modelGroup: group,
                                                   organization: org, releaseDate: date, score: raw * info.scale))
                }
                if name == "METR Time Horizons", let minutes = Double(r["Time horizon"] ?? ""), minutes > 0 {
                    horizons.append(TimeHorizon(modelVersion: version, modelGroup: group, organization: org,
                                                releaseDate: date, minutes: minutes))
                }
            }
        }
        if results.isEmpty { throw ParseError.empty("benchmark_data.zip") }
        return (infos, results, horizons)
    }

    /// Fallback when a version isn't in model_metadata: "gpt-6-luna_max" -> "gpt-6-luna".
    static func prettyGroup(_ version: String) -> String {
        let base = version.split(separator: "/").last.map(String.init) ?? version
        return base.split(separator: "_").first.map(String.init) ?? base
    }

    static func notableModels(_ text: String) throws -> [NotableModel] {
        let models: [NotableModel] = CSV.records(text).compactMap { r in
            guard let name = r["Model"], let date = Dates.parse(r["Publication date"]) else { return nil }
            let open = r["Open model weights?"] ?? ""
            return NotableModel(
                name: name,
                organization: r["Organization"] ?? "",
                date: date,
                domain: r["Domain"] ?? "",
                computeFLOP: Double(r["Training compute (FLOP)"] ?? ""),
                parameters: Double(r["Parameters"] ?? ""),
                isFrontier: r["Frontier model"] == "True",
                openWeights: open == "Yes" ? true : open == "No" ? false : nil)
        }
        if models.isEmpty { throw ParseError.empty("notable_ai_models.csv") }
        return models
    }
}

enum OpenRouterParser {
    private struct Response: Decodable { let data: [Model] }
    private struct Model: Decodable {
        let id: String
        let name: String
        let created: Double
        let context_length: Int?
        let architecture: Architecture?
        let pricing: Pricing?
    }
    private struct Architecture: Decodable {
        let input_modalities: [String]?
        let output_modalities: [String]?
    }
    private struct Pricing: Decodable {
        let prompt: String?
        let completion: String?
    }

    /// Keeps one entry per real model: drops routers, `:batch`/`:free` variants and unpriced entries.
    static func models(_ data: Data) throws -> [ListedModel] {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let models: [ListedModel] = decoded.data.compactMap { m in
            if m.id.contains(":") || m.id.hasPrefix("~") || m.id.hasPrefix("openrouter/") || m.id.hasPrefix("stealth/") { return nil }
            guard let input = Double(m.pricing?.prompt ?? ""), let output = Double(m.pricing?.completion ?? ""),
                  input >= 0, output >= 0 else { return nil }
            let parts = m.name.split(separator: ":", maxSplits: 1)
            let lab = parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespaces) : (m.id.split(separator: "/").first.map(String.init) ?? "")
            let name = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : m.name
            return ListedModel(
                id: m.id, name: name, lab: lab,
                created: Date(timeIntervalSince1970: m.created),
                contextLength: m.context_length ?? 0,
                inputPrice: input * 1_000_000, outputPrice: output * 1_000_000,
                inputModalities: Set(m.architecture?.input_modalities ?? ["text"]),
                outputModalities: Set(m.architecture?.output_modalities ?? ["text"]))
        }
        if models.isEmpty { throw ParseError.empty("OpenRouter model list") }
        return models
    }
}
