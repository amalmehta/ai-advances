import Foundation
import Observation

/// Loads the three public sources (bundled snapshot first, then the local cache),
/// and refreshes them from the web on launch and every few hours.
@MainActor
@Observable
final class DataStore {
    struct Source: Identifiable, Hashable {
        var id: String { file }
        let name: String
        let file: String
        let url: URL
        let credit: String
        let page: URL
    }

    struct SourceStatus: Hashable {
        var updated: Date?
        var fromSnapshot: Bool
        var error: String?
    }

    nonisolated static let sources: [Source] = [
        Source(name: "Epoch AI benchmarks", file: "benchmark_data.zip",
               url: URL(string: "https://epoch.ai/data/benchmark_data.zip")!,
               credit: "Epoch AI, ‘Capabilities & benchmarking’ (CC BY 4.0)",
               page: URL(string: "https://epoch.ai/benchmarks")!),
        Source(name: "Epoch AI notable models", file: "notable_ai_models.csv",
               url: URL(string: "https://epoch.ai/data/notable_ai_models.csv")!,
               credit: "Epoch AI, ‘Data on AI Models’ (CC BY 4.0)",
               page: URL(string: "https://epoch.ai/data/ai-models")!),
        Source(name: "OpenRouter model list", file: "openrouter_models.json",
               url: URL(string: "https://openrouter.ai/api/v1/models")!,
               credit: "OpenRouter public models API",
               page: URL(string: "https://openrouter.ai/models")!),
    ]

    static let staleAfter: TimeInterval = 12 * 3600
    static let checkEvery: TimeInterval = 6 * 3600

    private(set) var data = Dataset.empty
    private(set) var profiles: [ModelProfile] = []
    private(set) var status: [String: SourceStatus] = [:]
    private(set) var forecasts: [Forecast] = []
    /// Forecasts recomputed from the data available at the start of each past month.
    private(set) var reconstructedLog: [ForecastLogEntry] = []
    /// Forecasts saved on each day the app refreshed.
    private(set) var liveLog: [ForecastLogEntry] = []
    private(set) var labs: [LabSummary] = []
    /// How past forecasts did on milestones reached since.
    private(set) var trackRecord: TrackRecord?
    /// Written daily by Claude in the website build; nil until first downloaded.
    private(set) var claudeOutlook: ClaudeOutlook?

    nonisolated static let outlookURL = URL(string: "https://amalmehta.github.io/ai-advances/data/outlook.json")!
    nonisolated static var outlookCacheURL: URL { cacheDir.appendingPathComponent("Claude Outlook.json") }
    private(set) var isLoading = true
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date? {
        didSet { UserDefaults.standard.set(lastRefresh, forKey: "lastRefresh") }
    }
    var loadError: String?

    private var timer: Task<Void, Never>?

    init() {
        lastRefresh = UserDefaults.standard.object(forKey: "lastRefresh") as? Date
    }

    var latestDataDate: Date? {
        [data.results.map(\.releaseDate).max(), data.listed.map(\.created).max()].compactMap { $0 }.max()
    }

    nonisolated static var cacheDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AI Advances/Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() async {
        await reload()
        if lastRefresh.map({ Date().timeIntervalSince($0) > Self.staleAfter }) ?? true {
            await refresh()
        }
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.checkEvery))
                await self?.refresh()
            }
        }
    }

    /// Picks the cached copy of each source when present, else the bundled snapshot.
    private func fileURL(for source: Source) -> (URL, Bool) {
        let cached = Self.cacheDir.appendingPathComponent(source.file)
        if FileManager.default.fileExists(atPath: cached.path) { return (cached, false) }
        let seed = Bundle.main.url(forResource: (source.file as NSString).deletingPathExtension,
                                   withExtension: (source.file as NSString).pathExtension)!
        return (seed, true)
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        var files: [String: URL] = [:]
        for s in Self.sources {
            let (url, seed) = fileURL(for: s)
            files[s.file] = url
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            status[s.file] = SourceStatus(updated: seed ? nil : modified, fromSnapshot: seed, error: status[s.file]?.error)
        }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try Self.parseAll(files) }.value
            data = loaded
            profiles = Analysis.profiles(loaded)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            return
        }
        await recomputeOutlook()
        claudeOutlook = (try? Data(contentsOf: Self.outlookCacheURL)).flatMap { try? JSONDecoder().decode(ClaudeOutlook.self, from: $0) }
    }

    /// Forecasts, their history and the lab summaries; all derived from `data`, so rerun after every load.
    private func recomputeOutlook() async {
        let data = self.data, profiles = self.profiles, now = Date()
        let result = await Task.detached(priority: .utility) { () -> ([Forecast], [ForecastLogEntry], [ForecastLogEntry], [LabSummary], TrackRecord) in
            let current = Forecasts.all(data, profiles: profiles, asOf: now)
            let past = Forecasts.reconstructed(data, now: now)
            let log = ForecastLog.record(current, on: now, to: DataStore.forecastLogURL)
            let notes = (try? DataStore.bundled([LabNote].self, "Labs")) ?? []
            return (current, past, log, Labs.summaries(data, notes: notes, now: now),
                    TrackRecord.score(history: past + log, current: current))
        }.value
        (forecasts, reconstructedLog, liveLog, labs) = (result.0, result.1, result.2, result.3)
        trackRecord = result.4
    }

    /// Optional extra: a missing or malformed file just leaves the last good copy in place.
    private func downloadClaudeOutlook() async {
        guard let (data, response) = try? await URLSession.shared.data(from: Self.outlookURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder().decode(ClaudeOutlook.self, from: data)) != nil else { return }
        try? data.write(to: Self.outlookCacheURL, options: .atomic)
    }

    nonisolated static func parseAll(_ files: [String: URL]) throws -> Dataset {
        try Loader.parseAll(files, resources: Loader.Resources(
            capabilityAreas: Bundle.main.url(forResource: "CapabilityAreas", withExtension: "json")!,
            advances: Bundle.main.url(forResource: "Advances", withExtension: "json")!))
    }

    nonisolated static func bundled<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { throw ParseError.missing("\(name).json") }
        return try Loader.decode(T.self, from: url)
    }

    nonisolated static var forecastLogURL: URL {
        cacheDir.deletingLastPathComponent().appendingPathComponent("Forecast Log.json")
    }

    /// Downloads every source, checks it parses, then swaps it into the cache.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var anySuccess = false
        for s in Self.sources {
            do {
                var req = URLRequest(url: s.url, timeoutInterval: 60)
                req.setValue("AI Advances (Mac app)", forHTTPHeaderField: "User-Agent")
                let (tmp, response) = try await URLSession.shared.download(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                }
                try await Task.detached { try Loader.validate(file: s.file, at: tmp) }.value
                let dest = Self.cacheDir.appendingPathComponent(s.file)
                _ = try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                status[s.file]?.error = nil
                anySuccess = true
            } catch {
                status[s.file, default: SourceStatus(fromSnapshot: true)].error = error.localizedDescription
            }
        }
        await downloadClaudeOutlook()
        if anySuccess { lastRefresh = Date() }
        await reload()
    }
}
