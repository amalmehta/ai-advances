import Foundation

// ai-advances-export: builds the website's data from the same sources and analysis as the Mac app.
//
//   ai-advances-export --sources <dir> --resources <dir> --out <dir> [--log <file>] [--date yyyy-MM-dd]
//
// --sources   folder holding benchmark_data.zip, notable_ai_models.csv, openrouter_models.json
// --resources the app's Resources folder (CapabilityAreas.json, Advances.json, Labs.json)
// --out       where site.json is written
// --log       forecast log to read, add today's forecasts to, and write back

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard let sourcesDir = argument("--sources"), let resourcesDir = argument("--resources"), let outDir = argument("--out") else {
    fail("usage: ai-advances-export --sources <dir> --resources <dir> --out <dir> [--log <file>] [--date yyyy-MM-dd]")
}

let sources = URL(fileURLWithPath: sourcesDir)
let resources = URL(fileURLWithPath: resourcesDir)
let now = argument("--date").flatMap(Dates.parse) ?? Date()
let files = Dictionary(uniqueKeysWithValues: ["benchmark_data.zip", "notable_ai_models.csv", "openrouter_models.json"].map {
    ($0, sources.appendingPathComponent($0))
})

let data: Dataset
do {
    data = try Loader.parseAll(files, resources: Loader.Resources(
        capabilityAreas: resources.appendingPathComponent("CapabilityAreas.json"),
        advances: resources.appendingPathComponent("Advances.json")))
} catch {
    fail("Couldn't parse sources: \(error.localizedDescription)")
}
let notes = (try? Loader.decode([LabNote].self, from: resources.appendingPathComponent("Labs.json"))) ?? []

let site = Export.build(data, notes: notes, now: now, logURL: argument("--log").map(URL.init(fileURLWithPath:)))

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .formatted(Dates.day)
encoder.outputFormatting = [.sortedKeys]
do {
    let out = URL(fileURLWithPath: outDir)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let json = try encoder.encode(site)
    try json.write(to: out.appendingPathComponent("site.json"), options: .atomic)
    print("Wrote \(out.appendingPathComponent("site.json").path) (\(json.count / 1024) KB): "
          + "\(site.results.count) results, \(site.models.count) models, \(site.forecasts.count) forecasts, "
          + "\(site.history.count) history entries, \(site.labs.count) labs")
} catch {
    fail("Couldn't write output: \(error.localizedDescription)")
}
