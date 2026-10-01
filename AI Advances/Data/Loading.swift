import Foundation

/// Parses the raw source files into a `Dataset`. Shared by the Mac app and the website exporter,
/// so it only uses Foundation and tools present on both macOS and Linux.
enum Loader {
    struct Resources {
        let capabilityAreas: URL
        let advances: URL
    }

    static func parseAll(_ files: [String: URL], resources: Resources) throws -> Dataset {
        var d = Dataset()
        let unzipped = FileManager.default.temporaryDirectory.appendingPathComponent("ai-advances-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: unzipped) }
        try unzip(files["benchmark_data.zip"]!, to: unzipped)
        (d.benchmarks, d.results, d.horizons) = try EpochParser.benchmarks(in: unzipped)
        d.notable = try EpochParser.notableModels(String(contentsOf: files["notable_ai_models.csv"]!, encoding: .utf8))
        d.listed = try OpenRouterParser.models(Data(contentsOf: files["openrouter_models.json"]!))
        d.areas = try decode([CapabilityArea].self, from: resources.capabilityAreas)
        d.advances = try decode([Advance].self, from: resources.advances).sorted { $0.day > $1.day }
        return d
    }

    static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func unzip(_ zip: URL, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-q", "-o", zip.path, "-d", dir.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw ParseError.missing("contents of \(zip.lastPathComponent)") }
    }

    /// Checks a freshly downloaded source file parses before it replaces the old copy.
    static func validate(file: String, at url: URL) throws {
        switch file {
        case "benchmark_data.zip":
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ai-advances-check-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            try unzip(url, to: dir)
            _ = try EpochParser.benchmarks(in: dir)
        case "notable_ai_models.csv":
            _ = try EpochParser.notableModels(String(contentsOf: url, encoding: .utf8))
        default:
            _ = try OpenRouterParser.models(Data(contentsOf: url))
        }
    }
}
