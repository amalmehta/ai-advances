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
    struct Parsed {
        var infos: [BenchmarkInfo] = []
        var results: [BenchmarkResult] = []
        var horizons: [TimeHorizon] = []
        var warnings: [String] = []
        /// Rows kept only thanks to a fallback (release date from model_metadata, version from "Name").
        var recoveredRows = 0
    }

    /// Where a tracked benchmark's results live when Epoch's metadata loses its `source_file` or
    /// `score_column` (HLE and DeepSWE on Oct 20, 2026, while their files were still in the zip).
    static let fallbackSources: [String: (file: String, column: String)] = [
        "HLE": ("hle_external.csv", "Accuracy"),
        "DeepSWE": ("deepswe_external.csv", "Pass@1"),
        "WeirdML v3": ("weirdml_v3_external.csv", "Max performance"),
    ]

    /// Parses the unzipped `benchmark_data.zip` folder.
    static func benchmarks(in dir: URL) throws -> (infos: [BenchmarkInfo], results: [BenchmarkResult], horizons: [TimeHorizon]) {
        let p = try parse(in: dir)
        return (p.infos, p.results, p.horizons)
    }

    /// Lowercase letters and digits only, for matching a benchmark name to a file name.
    static func slug(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }

    /// The results file for a benchmark whose metadata has no `source_file`: the curated fallback,
    /// else a file named after the benchmark ("<slug>_external.csv" or "<slug>.csv", ignoring case
    /// and punctuation).
    static func fallbackFile(for benchmark: String, among files: [String]) -> String? {
        if let f = fallbackSources[benchmark]?.file, files.contains(f) { return f }
        let want = slug(benchmark)
        return files.first { f in
            guard f.lowercased().hasSuffix(".csv") else { return false }
            let stem = slug(String(f.dropLast(4)))
            return stem == want + "external" || stem == want
        }
    }

    /// Parses the folder. `tracked` benchmarks also get the file-name fallback when they have no
    /// curated one; others with no `source_file` are skipped as before.
    static func parse(in dir: URL, tracked: Set<String> = []) throws -> Parsed {
        let metaURL = dir.appendingPathComponent("benchmark_metadata.csv")
        guard let metaText = try? String(contentsOf: metaURL, encoding: .utf8) else { throw ParseError.missing("benchmark_metadata.csv") }

        var groups: [String: (group: String, org: String, date: Date?)] = [:]
        if let text = try? String(contentsOf: dir.appendingPathComponent("model_metadata.csv"), encoding: .utf8) {
            for r in CSV.records(text) {
                guard let v = r["model_version"], !v.isEmpty, let g = r["model_group"], !g.isEmpty else { continue }
                groups[v] = (g, r["organization"] ?? "", Dates.parse(r["date"]))
            }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []

        var out = Parsed()
        for m in CSV.records(metaText) {
            guard let name = m["benchmark"], !name.isEmpty else { continue }
            var file = m["source_file"] ?? ""
            var column = m["score_column"] ?? ""
            if file.isEmpty || column.isEmpty {
                guard fallbackSources[name] != nil || tracked.contains(name),
                      let f = file.isEmpty ? fallbackFile(for: name, among: files) : file else { continue }
                file = f
                if column.isEmpty {
                    let header = (try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8))
                        .flatMap { CSV.rows(String($0.prefix(4096))).first } ?? []
                    guard let c = [fallbackSources[name]?.column, "Score", "Accuracy"].compactMap({ $0 }).first(where: header.contains)
                    else { continue }
                    column = c
                }
                out.warnings.append("\(name): Epoch's metadata names no source file or score column; read \(file) (\(column)) instead.")
            }
            let info = BenchmarkInfo(
                name: name, sourceFile: file, scoreColumn: column,
                scale: Double(m["scale"] ?? "") ?? 1,
                randomBaseline: Double(m["random_baseline"] ?? "") ?? 0,
                ceiling: Double(m["score_ceiling"] ?? "") ?? 1,
                releaseDate: Dates.parse(m["release_date"]),
                supersededBy: (m["superseded_by"]?.isEmpty ?? true) ? nil : m["superseded_by"])
            guard let text = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else { continue }
            out.infos.append(info)

            for r in CSV.records(text) {
                // A row with no version is still a model if it has a name; one with no release
                // date can take it from model_metadata.
                let versionCell = r["Model version"] ?? ""
                let version = versionCell.isEmpty ? (r["Name"] ?? "") : versionCell
                guard !version.isEmpty else { continue }
                let meta = groups[version]
                let parsedDate = Dates.parse(r["Release date"])
                guard let date = parsedDate ?? meta?.date else { continue }
                let group = meta?.group ?? prettyGroup(version)
                let org = (r["Organization"]?.isEmpty == false ? r["Organization"]! : meta?.org) ?? ""
                if let raw = Double(r[column] ?? "") {
                    if versionCell.isEmpty || parsedDate == nil { out.recoveredRows += 1 }
                    out.results.append(BenchmarkResult(benchmark: name, modelVersion: version, modelGroup: group,
                                                       organization: org, releaseDate: date, score: raw * info.scale))
                }
                if name == "METR Time Horizons", let minutes = Double(r["Time horizon"] ?? ""), minutes > 0 {
                    out.horizons.append(TimeHorizon(modelVersion: version, modelGroup: group, organization: org,
                                                    releaseDate: date, minutes: minutes,
                                                    averageScore: Double(r["average_score"] ?? "")))
                }
            }
        }
        if out.results.isEmpty { throw ParseError.empty("benchmark_data.zip") }
        return out
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
