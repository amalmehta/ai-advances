import AppKit
import Foundation
import Network
import Observation

/// Loads the three public sources (bundled snapshot first, then the local cache),
/// and refreshes them from the web on launch and every morning.
@MainActor
@Observable
final class DataStore {
    struct Source: Identifiable, Hashable, Sendable {
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
        /// Newest entry in this source's data, so the snapshot's date comes from the data itself.
        var newestEntry: Date?
    }

    /// How the store reaches the network; tests swap in `.offline` so they never download anything.
    struct Transport: Sendable {
        var download: @Sendable (URLRequest) async throws -> (URL, URLResponse)
        var data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

        static let live = Transport(download: { try await URLSession.shared.download(for: $0) },
                                  data: { try await URLSession.shared.data(for: $0) })
        static let offline = Transport(download: { _ in throw URLError(.notConnectedToInternet) },
                                     data: { _ in throw URLError(.notConnectedToInternet) })
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

    nonisolated static let websiteURL = URL(string: "https://amalmehta.github.io/ai-advances/")!
    nonisolated static let latestReleaseAPI = URL(string: "https://api.github.com/repos/amalmehta/ai-advances/releases/latest")!
    nonisolated static let outlookURL = URL(string: "https://amalmehta.github.io/ai-advances/data/outlook.json")!

    // MARK: Environment

    /// True inside the unit-test host, where the app must not touch the user's data or the network.
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// ~/Library/Application Support/AI Advances, unless AI_ADVANCES_DATA_DIR points elsewhere
    /// (UI tests and screenshots use that to keep away from the real data).
    nonisolated static var defaultStorageDir: URL {
        if let dir = ProcessInfo.processInfo.environment["AI_ADVANCES_DATA_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AI Advances", isDirectory: true)
    }

    /// Holds the cached sources (in Data/), the forecast log and the downloaded outlook. Created on
    /// first use.
    let storageDir: URL
    let defaults: UserDefaults
    private let network: Transport
    private let parse: @Sendable ([String: URL]) throws -> Dataset

    var cacheDir: URL {
        let dir = storageDir.appendingPathComponent("Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    var forecastLogURL: URL { storageDir.appendingPathComponent("Forecast Log.json") }
    var outlookCacheURL: URL { cacheDir.appendingPathComponent("Claude Outlook.json") }

    // MARK: State

    private(set) var data = Dataset.empty
    private(set) var profiles: [ModelProfile] = []
    /// Analysis derived from `data`, computed once per load rather than in view bodies.
    private(set) var derived = Derived()
    private(set) var status: [String: SourceStatus] = [:]
    private(set) var forecasts: [Forecast] = []
    /// Forecasts recomputed from the data available at the start of each past month.
    private(set) var reconstructedLog: [ForecastLogEntry] = []
    /// Forecasts saved on each day the app refreshed.
    private(set) var liveLog: [ForecastLogEntry] = []
    private(set) var labs: [LabSummary] = []
    /// How past forecasts did on milestones reached since.
    private(set) var trackRecord: TrackRecord?
    /// Feed items that appeared since you last opened Latest Advances.
    private(set) var newFeedIDs: Set<String> = []
    static let seenFeedKey = "seenFeedIDs"

    /// Set when GitHub has a newer release than this copy of the app.
    private(set) var update: (version: String, page: URL)?
    /// The answer to a "Check for Updates…" the user asked for, shown as an alert.
    var updateCheckMessage: String?

    /// Written daily by Claude in the website build; nil until first downloaded.
    private(set) var claudeOutlook: ClaudeOutlook?

    private(set) var isLoading = true
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date? {
        didSet { defaults.set(lastRefresh, forKey: "lastRefresh") }
    }
    var loadError: String?
    /// Why the last refresh failed (for any source); cleared by the next full success.
    var refreshError: String?
    /// Number of reloads started; lets tests check a refresh that changed nothing didn't reparse.
    private(set) var reloadCount = 0

    /// Tests that don't look at forecasts turn this off to skip the slowest part of a load.
    var computesForecasts = true
    private var started = false
    private var loadGeneration = 0
    private var timer: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var wakeObserver: NSObjectProtocol?
    private var pathMonitor: NWPathMonitor?
    private var networkWasUp: Bool?
    private var updateCheckInFlight = false
    private var lastUpdateAttempt: Date?
    /// Sources whose cached copy failed to parse; the bundled snapshot is used until a refresh replaces them.
    private var brokenCache: Set<String> = []

    /// Waits before retrying a failed refresh: 5, 15, then 60 minutes.
    nonisolated static let retryDelays: [Duration] = [.seconds(5 * 60), .seconds(15 * 60), .seconds(60 * 60)]
    /// Data older than this gets a warning banner, like the website's.
    nonisolated static let staleAfterDays = 2

    /// - Parameters: everything defaults to the real app's locations, except under XCTest, where
    ///   storage goes to a fresh temporary folder, settings to a separate defaults suite, and the
    ///   network is off.
    init(storageDir: URL? = nil, defaults: UserDefaults? = nil, network: Transport? = nil,
         parse: (@Sendable ([String: URL]) throws -> Dataset)? = nil) {
        let testing = Self.isRunningTests
        self.storageDir = storageDir ?? (testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("AI Advances Tests \(UUID().uuidString)", isDirectory: true)
            : Self.defaultStorageDir)
        if let defaults {
            self.defaults = defaults
        } else if let suite = ProcessInfo.processInfo.environment["AI_ADVANCES_DEFAULTS_SUITE"], let d = UserDefaults(suiteName: suite) {
            self.defaults = d
        } else {
            self.defaults = testing ? UserDefaults(suiteName: "com.amalmehta.ai-advances.unit-tests")! : .standard
        }
        self.network = network ?? (testing ? .offline : .live)
        self.parse = parse ?? { try DataStore.parseAll($0) }
        lastRefresh = self.defaults.object(forKey: "lastRefresh") as? Date
    }

    var latestDataDate: Date? {
        [data.results.map(\.releaseDate).max(), data.listed.map(\.created).max()].compactMap { $0 }.max()
    }

    // MARK: Lifecycle

    /// Loads the data and starts the morning schedule. Runs once per launch, however many times
    /// the window appears.
    func start() async {
        guard !started else { return }
        started = true
        await reload()
        await checkForUpdate()
        await refreshIfMorningPassed()
        // Refresh at 7:00 AM each day while the app is open...
        timer = Task { [weak self] in
            while !Task.isCancelled {
                let wait = MorningSchedule.nextMorning(after: Date()).timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(max(60, wait)))
                await self?.refreshIfMorningPassed()
            }
        }
        // ...and on waking, in case the Mac was asleep at 7.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfMorningPassed() }
        }
        // ...and when the network comes back after a failed refresh.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(up: up) }
        }
        monitor.start(queue: DispatchQueue(label: "AI Advances network monitor"))
        pathMonitor = monitor
    }

    /// Refreshes once a 7:00 AM has passed since the last refresh.
    func refreshIfMorningPassed() async {
        if MorningSchedule.needsRefresh(lastRefresh: lastRefresh, now: Date()) { await refresh() }
    }

    private func networkChanged(up: Bool) {
        defer { networkWasUp = up }
        guard up, networkWasUp == false, !isRefreshing else { return }
        if refreshError != nil || MorningSchedule.needsRefresh(lastRefresh: lastRefresh, now: Date()) {
            Task { await refresh() }
        }
    }

    // MARK: Loading

    /// Picks the cached copy of each source when present (and readable), else the bundled snapshot.
    private func fileURL(for source: Source) -> (URL, Bool) {
        let cached = cacheDir.appendingPathComponent(source.file)
        if !brokenCache.contains(source.file), FileManager.default.fileExists(atPath: cached.path) { return (cached, false) }
        return (Self.bundledURL(source.file), true)
    }

    nonisolated static func bundledURL(_ file: String) -> URL {
        Bundle.main.url(forResource: (file as NSString).deletingPathExtension,
                        withExtension: (file as NSString).pathExtension)!
    }

    /// Reparses every source. Overlapping calls are fine: only the newest one's results are kept.
    func reload() async {
        loadGeneration += 1
        reloadCount += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }

        var files: [String: URL] = [:]
        var fromSnapshot: Set<String> = []
        for s in Self.sources {
            let (url, seed) = fileURL(for: s)
            files[s.file] = url
            if seed { fromSnapshot.insert(s.file) }
        }
        let parse = self.parse, now = Date(), toParse = files, seeds = fromSnapshot
        let outcome: LoadOutcome
        do {
            outcome = try await Self.runBlocking { try Self.load(toParse, fromSnapshot: seeds, parse: parse, now: now) }
        } catch {
            guard generation == loadGeneration else { return }
            loadError = error.localizedDescription
            return
        }
        guard generation == loadGeneration else { return } // a newer reload started meanwhile

        for s in Self.sources {
            let fellBack = outcome.fellBack[s.file]
            if fellBack != nil { brokenCache.insert(s.file) }
            let seed = fromSnapshot.contains(s.file) || fellBack != nil
            let url = seed ? Self.bundledURL(s.file) : files[s.file]!
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let error = fellBack.map { "The downloaded copy couldn't be read (\($0)), so the bundled snapshot is in use until the next update." }
                ?? status[s.file]?.error
            status[s.file] = SourceStatus(updated: seed ? nil : modified, fromSnapshot: seed, error: error,
                                          newestEntry: outcome.derived.newestEntry[s.file])
        }
        data = outcome.data
        profiles = outcome.profiles
        derived = outcome.derived
        updateNewFeed() // before any page can show the feed
        loadError = nil
        loadOutlookFromCache()
        if computesForecasts { await recomputeOutlook(generation: generation) }
    }

    private struct LoadOutcome: @unchecked Sendable {
        let data: Dataset
        let profiles: [ModelProfile]
        let derived: Derived
        /// Sources whose cached copy failed, with the reason.
        let fellBack: [String: String]
    }

    /// Parses the files; if that fails, checks each cached file on its own and swaps any bad one
    /// for the bundled snapshot before trying again.
    nonisolated private static func load(_ files: [String: URL], fromSnapshot: Set<String>,
                                         parse: ([String: URL]) throws -> Dataset, now: Date) throws -> LoadOutcome {
        var files = files
        var fellBack: [String: String] = [:]
        let data: Dataset
        do {
            data = try parse(files)
        } catch {
            for (file, url) in files where !fromSnapshot.contains(file) {
                do { try Loader.validate(file: file, at: url) } catch let bad {
                    fellBack[file] = bad.localizedDescription
                    files[file] = bundledURL(file)
                }
            }
            if fellBack.isEmpty { throw error }
            data = try parse(files)
        }
        let profiles = Analysis.profiles(data)
        return LoadOutcome(data: data, profiles: profiles, derived: Derived(data, profiles: profiles, now: now), fellBack: fellBack)
    }

    /// Clears the "use the snapshot" fallbacks and loads again.
    func retryLoading() async {
        brokenCache = []
        for file in status.keys { status[file]?.error = nil }
        await reload()
    }

    /// Deletes the downloaded copies, so the app runs on the snapshot bundled with it until the next update.
    func resetToBundledData() async {
        for s in Self.sources {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(s.file))
            status[s.file]?.error = nil
        }
        brokenCache = []
        await reload()
    }

    /// Compares the current feed with what was there when you last looked. On first run nothing
    /// counts as new, so you aren't greeted by the whole feed.
    private func updateNewFeed() {
        let ids = derived.feed.map(\.id)
        guard let seen = defaults.stringArray(forKey: Self.seenFeedKey) else {
            defaults.set(ids, forKey: Self.seenFeedKey)
            return
        }
        newFeedIDs = Set(ids).subtracting(seen)
    }

    /// Called when Latest Advances is shown.
    func markFeedSeen() {
        guard !data.results.isEmpty else { return }
        defaults.set(derived.feed.map(\.id), forKey: Self.seenFeedKey)
        newFeedIDs = []
    }

    /// Forecasts, their history and the lab summaries; all derived from `data`, so rerun after every load.
    private func recomputeOutlook(generation: Int) async {
        let data = self.data, profiles = self.profiles, now = Date(), logURL = forecastLogURL
        let result = await Task.detached(priority: .utility) { () -> ([Forecast], [ForecastLogEntry], [ForecastLogEntry], [LabSummary], TrackRecord) in
            let current = Forecasts.all(data, profiles: profiles, asOf: now)
            let past = Forecasts.reconstructed(data, now: now)
            let log: [ForecastLogEntry]
            do {
                log = try ForecastLog.record(current, on: now, to: logURL)
            } catch {
                // A damaged local log is set aside (not deleted) and a new one started.
                try? FileManager.default.moveItem(at: logURL, to: logURL.deletingPathExtension().appendingPathExtension("damaged-\(Int(now.timeIntervalSince1970)).json"))
                log = (try? ForecastLog.record(current, on: now, to: logURL)) ?? []
            }
            let notes = (try? DataStore.bundled([LabNote].self, "Labs")) ?? []
            return (current, past, log, Labs.summaries(data, notes: notes, now: now),
                    TrackRecord.score(history: past + log, current: current))
        }.value
        guard generation == loadGeneration else { return }
        (forecasts, reconstructedLog, liveLog, labs) = (result.0, result.1, result.2, result.3)
        trackRecord = result.4
    }

    private func loadOutlookFromCache() {
        claudeOutlook = (try? Data(contentsOf: outlookCacheURL)).flatMap { try? JSONDecoder().decode(ClaudeOutlook.self, from: $0) }
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

    /// Runs blocking work (parsing waits on /usr/bin/unzip) on its own thread rather than
    /// tying up one of Swift concurrency's few shared threads.
    nonisolated static func runBlocking<T>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { continuation.resume(with: Result { try work() }) }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    // MARK: Updates of the app

    /// Asks GitHub for the latest release, at most once a day unless the user asks. Quiet on any
    /// failure unless the user asked.
    func checkForUpdate(manual: Bool = false) async {
        let key = "lastUpdateCheck"
        if !manual {
            // At most once a day: tried (even if it failed) in this session, or succeeded in an earlier one.
            let recent = { (d: Date?) in d.map { Date().timeIntervalSince($0) < 86_400 } ?? false }
            if recent(lastUpdateAttempt) || recent(defaults.object(forKey: key) as? Date) { return }
        }
        guard !updateCheckInFlight else { return }
        lastUpdateAttempt = Date()
        updateCheckInFlight = true
        defer { updateCheckInFlight = false }

        struct Release: Decodable { let tag_name: String; let html_url: URL; let draft: Bool?; let prerelease: Bool? }
        var req = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AI Advances (Mac app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await network.data(req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true else {
            if manual { updateCheckMessage = "Couldn't reach GitHub to check for updates. Try again later." }
            return
        }
        defaults.set(Date(), forKey: key)
        let current = Self.appVersion
        update = AppVersion.isNewer(release.tag_name, than: current)
            ? (String(release.tag_name.drop { $0 == "v" }), release.html_url) : nil
        if manual {
            updateCheckMessage = update.map { "Version \($0.version) is available. Use the button in the toolbar to open the download page." }
                ?? "You have the latest version (\(current))."
        }
    }

    nonisolated static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Refreshing the data

    /// Downloads every source at once, checks each parses, then swaps it into the cache. Reloads
    /// only if something actually changed; on any failure, retries later.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        retryTask?.cancel()
        retryTask = nil
        defer { isRefreshing = false }

        let dir = cacheDir, network = self.network
        let results = await withTaskGroup(of: (String, String?, Bool).self) { group in
            for s in Self.sources {
                group.addTask {
                    do { return (s.file, nil, try await Self.fetch(s, into: dir, network: network)) }
                    catch { return (s.file, error.localizedDescription, false) }
                }
            }
            var out: [(String, String?, Bool)] = []
            for await r in group { out.append(r) }
            return out
        }

        var changed = false
        var failures: [String] = []
        for (file, error, didChange) in results {
            if let error {
                status[file, default: SourceStatus(fromSnapshot: true)].error = error
                failures.append("\(Self.sources.first { $0.file == file }?.name ?? file): \(error)")
            } else {
                status[file]?.error = nil
                if brokenCache.remove(file) != nil { changed = true }
                changed = changed || didChange
            }
        }
        let outlookChanged = await downloadClaudeOutlook()
        await checkForUpdate()
        if failures.count < Self.sources.count { lastRefresh = Date() }

        if failures.isEmpty {
            refreshError = nil
            retryAttempt = 0
        } else {
            refreshError = failures.sorted().joined(separator: "\n")
            scheduleRetry()
        }
        if changed || data.results.isEmpty {
            await reload()
        } else if outlookChanged {
            loadOutlookFromCache()
        }
    }

    private func scheduleRetry() {
        guard started, retryAttempt < Self.retryDelays.count else { return }
        let delay = Self.retryDelays[retryAttempt]
        retryAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil // so refresh() doesn't cancel the task it's running in
            await self.refresh()
        }
    }

    /// Downloads one source and installs it. Returns whether the cached copy changed.
    nonisolated private static func fetch(_ s: Source, into dir: URL, network: Transport) async throws -> Bool {
        var req = URLRequest(url: s.url, timeoutInterval: 60)
        req.setValue("AI Advances (Mac app)", forHTTPHeaderField: "User-Agent")
        let (tmp, response) = try await network.download(req)
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return try await runBlocking {
            try Loader.validate(file: s.file, at: tmp)
            return try install(tmp, as: s.file, in: dir)
        }
    }

    /// Puts a downloaded file in place of the cached one atomically (the old copy stays until the
    /// new one is fully in place). Returns false, leaving the cache untouched, when the contents
    /// are identical.
    nonisolated static func install(_ downloaded: URL, as file: String, in dir: URL) throws -> Bool {
        let fm = FileManager.default
        let dest = dir.appendingPathComponent(file)
        if fm.fileExists(atPath: dest.path), fm.contentsEqual(atPath: dest.path, andPath: downloaded.path) { return false }
        // Stage next to the destination first, so the final swap is on one volume.
        let staged = dir.appendingPathComponent(".\(file).\(UUID().uuidString).download")
        try fm.copyItem(at: downloaded, to: staged)
        do {
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: dest)
            }
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        return true
    }

    /// Optional extra: a missing or malformed file just leaves the last good copy in place.
    /// Returns whether the cached copy changed.
    private func downloadClaudeOutlook() async -> Bool {
        guard let (data, response) = try? await network.data(URLRequest(url: Self.outlookURL, timeoutInterval: 30)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder().decode(ClaudeOutlook.self, from: data)) != nil else { return false }
        if (try? Data(contentsOf: outlookCacheURL)) == data { return false }
        try? data.write(to: outlookCacheURL, options: .atomic)
        return true
    }

    // MARK: Staleness

    /// Days since the data was last refreshed or since its newest entry, whichever is longer, when
    /// that's more than `staleAfterDays`; nil when the data is current. Never refreshed means the
    /// bundled snapshot, whose age is its newest entry's.
    nonisolated static func staleDays(lastRefresh: Date?, latestData: Date?, now: Date) -> Int? {
        let age = [lastRefresh, latestData].compactMap { $0 }.map { Int(now.timeIntervalSince($0) / 86_400) }.max() ?? 0
        return age > staleAfterDays ? age : nil
    }
}

/// Analysis the pages show, computed once per data load (off the main thread) instead of in view
/// bodies, where it reran on every hover.
struct Derived: @unchecked Sendable {
    static let momentumWindows = [6, 12, 24]

    var feed: [FeedItem] = []
    /// Area momentum for each window in `momentumWindows`, fastest first.
    var momentum: [Int: [AreaMomentum]] = [:]
    /// Record-setting results for every benchmark that has results.
    var frontiers: [String: [FrontierPoint]] = [:]
    var computeFit: ExpFit?
    var horizons: [TimeHorizon] = []
    var horizonFit: ExpFit?
    var gpqaPrice: [PriceStep] = []
    var maxContext = 0
    var recentMedianContext: Double?
    /// Newest entry per source file.
    var newestEntry: [String: Date] = [:]

    init() {}

    init(_ data: Dataset, profiles: [ModelProfile], now: Date) {
        feed = Feed.items(data, now: now)
        for m in Self.momentumWindows {
            momentum[m] = data.areas.compactMap {
                Analysis.momentum(area: $0, results: data.results, infos: data.benchmarks, now: now, months: m)
            }
            .sorted { $0.gapClosed > $1.gapClosed }
        }
        for b in Set(data.results.map(\.benchmark)) {
            frontiers[b] = Analysis.frontier(data.results, benchmark: b)
        }
        computeFit = Analysis.computeFit(data.notable, since: Dates.parse("2020-01-01")!)
        horizons = Analysis.horizonFrontier(data.horizons)
        horizonFit = ExpFit.fit(horizons.filter { $0.releaseDate >= Dates.parse("2023-01-01")! }.map { ($0.releaseDate, $0.minutes) })
        gpqaPrice = Analysis.cheapestOverTime(profiles, benchmark: "GPQA diamond", threshold: 0.8)
        maxContext = data.listed.map(\.contextLength).max() ?? 0
        recentMedianContext = Analysis.medianContextByQuarter(data.listed, since: now.addingTimeInterval(-365.25 * 86_400)).last?.1
        newestEntry = [
            "benchmark_data.zip": [data.results.map(\.releaseDate).max(), data.horizons.map(\.releaseDate).max()].compactMap { $0 }.max(),
            "notable_ai_models.csv": data.notable.map(\.date).max(),
            "openrouter_models.json": data.listed.map(\.created).max(),
        ].compactMapValues { $0 }
    }
}
