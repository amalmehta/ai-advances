import XCTest
import SwiftUI
@testable import AI_Advances

/// The app layer: the data store's loading, refreshing and isolation, and view helpers.
@MainActor
final class DataStoreTests: XCTestCase {
    /// One shared suite (tests run one at a time), emptied around each test, so test runs don't
    /// leave a preferences file per store behind.
    static let suite = "com.amalmehta.ai-advances.unit-tests"
    private var dirs: [URL] = []

    override func setUp() async throws {
        UserDefaults.standard.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() async throws {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs = []
        UserDefaults.standard.removePersistentDomain(forName: Self.suite)
    }

    /// A store in its own temporary folder and defaults suite.
    private func makeStore(network: DataStore.Transport = .offline,
                           parse: (@Sendable ([String: URL]) throws -> Dataset)? = nil) -> DataStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppTests-\(UUID().uuidString)", isDirectory: true)
        dirs.append(dir)
        return DataStore(storageDir: dir, defaults: UserDefaults(suiteName: Self.suite)!, network: network, parse: parse)
    }

    // 54
    func testUnitTestsNeverTouchTheRealAppData() {
        XCTAssertTrue(DataStore.isRunningTests)
        XCTAssertFalse(AIAdvancesApp.shouldStartStore, "the test host app must not start loading and refreshing")
        let store = DataStore()
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertFalse(store.storageDir.path.hasPrefix(real.path), "default store in tests should use a temporary folder")
        XCTAssertFalse(store.forecastLogURL.path.hasPrefix(real.path))
        XCTAssertFalse(store.defaults === UserDefaults.standard, "tests must not write the app's own defaults")
        dirs.append(store.storageDir)
    }

    // 55
    func testOverlappingReloadsKeepTheNewestResult() async throws {
        final class Calls: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
        }
        let calls = Calls()
        let full = try XCTUnwrap(SnapshotTests.data)
        let store = makeStore(parse: { _ in
            var d = full
            if calls.next() == 1 {
                Thread.sleep(forTimeInterval: 1.5) // the first (older) load finishes last...
                d.advances = Array(d.advances.prefix(1))
            }
            return d
        })
        async let first: Void = store.reload()
        try await Task.sleep(for: .milliseconds(200))
        async let second: Void = store.reload()
        _ = await (first, second)
        // ...but its result must not overwrite the newer one.
        XCTAssertEqual(store.data.advances.count, full.advances.count)
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.forecasts.isEmpty)
    }

    // 57
    func testUnreadableCachedSourceFallsBackToTheBundledSnapshot() async throws {
        let store = makeStore()
        store.computesForecasts = false
        try Data("not,a,valid\nfile".utf8).write(to: store.cacheDir.appendingPathComponent("notable_ai_models.csv"))
        try Data("{ broken".utf8).write(to: store.cacheDir.appendingPathComponent("openrouter_models.json"))
        await store.reload()
        XCTAssertNil(store.loadError)
        XCTAssertFalse(store.data.results.isEmpty)
        XCTAssertFalse(store.data.listed.isEmpty, "the bundled OpenRouter list is used instead")
        let st = try XCTUnwrap(store.status["openrouter_models.json"])
        XCTAssertTrue(st.fromSnapshot)
        XCTAssertNotNil(st.error)
        XCTAssertNotNil(st.newestEntry, "the snapshot's date comes from its data")

        await store.resetToBundledData()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.cacheDir.appendingPathComponent("openrouter_models.json").path))
        XCTAssertNil(store.status["openrouter_models.json"]?.error)
        XCTAssertTrue(store.status.values.allSatisfy(\.fromSnapshot))
    }

    // 58
    func testInstallReplacesAtomicallyAndSkipsIdenticalFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppTests-\(UUID().uuidString)", isDirectory: true)
        dirs.append(dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.tmp"), b = dir.appendingPathComponent("b.tmp")
        try Data("one".utf8).write(to: a)
        try Data("two".utf8).write(to: b)

        XCTAssertTrue(try DataStore.install(a, as: "x.json", in: dir), "first install")
        XCTAssertFalse(try DataStore.install(a, as: "x.json", in: dir), "identical contents change nothing")
        XCTAssertTrue(try DataStore.install(b, as: "x.json", in: dir))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("x.json"), encoding: .utf8), "two")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".download") }
        XCTAssertEqual(leftovers, [], "no staging files left behind")
    }

    // 58, 60
    func testRefreshReloadsOnlyWhenSomethingChangedAndReportsFailures() async throws {
        let serveBundled = DataStore.Transport(download: { req in
            let file = try XCTUnwrap(DataStore.sources.first { $0.url == req.url }).file
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: DataStore.bundledURL(file), to: tmp)
            return (tmp, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, data: { _ in throw URLError(.notConnectedToInternet) })
        // Parsing is covered elsewhere; reuse the parsed snapshot to keep this quick.
        let snapshot = try XCTUnwrap(SnapshotTests.data)
        let store = makeStore(network: serveBundled, parse: { _ in snapshot })
        store.computesForecasts = false
        await store.reload()
        XCTAssertEqual(store.reloadCount, 1)

        await store.refresh()
        XCTAssertEqual(store.reloadCount, 2, "new files were installed, so the data reloads")
        XCTAssertNil(store.refreshError)
        XCTAssertNotNil(store.lastRefresh)
        XCTAssertTrue(store.status.values.allSatisfy { !$0.fromSnapshot })

        await store.refresh()
        XCTAssertEqual(store.reloadCount, 2, "identical downloads don't reparse everything")

        UserDefaults.standard.removePersistentDomain(forName: Self.suite) // forget the first store's lastRefresh
        let offline = makeStore(network: .offline, parse: { _ in snapshot })
        offline.computesForecasts = false
        await offline.reload()
        await offline.refresh()
        XCTAssertNotNil(offline.refreshError, "a failed refresh is reported")
        XCTAssertNil(offline.lastRefresh)
        XCTAssertEqual(offline.reloadCount, 1)
    }

    // 59
    func testStaleAfterTwoDays() {
        let now = Dates.parse("2026-10-20")!
        let day: TimeInterval = 86_400
        XCTAssertNil(DataStore.staleDays(lastRefresh: now - day, latestData: now - day, now: now))
        XCTAssertEqual(DataStore.staleDays(lastRefresh: now - 5 * day, latestData: now - day, now: now), 5)
        XCTAssertEqual(DataStore.staleDays(lastRefresh: now - day, latestData: now - 4 * day, now: now), 4)
        XCTAssertEqual(DataStore.staleDays(lastRefresh: nil, latestData: now - 20 * day, now: now), 20, "never refreshed: the snapshot's age")
    }
}

final class AppHelperTests: XCTestCase {
    // 69
    func testPickersFallBackToARealOption() {
        XCTAssertEqual(effectiveSelection("", among: ["a", "b"]), "a")
        XCTAssertEqual(effectiveSelection("gone", among: ["a", "b"]), "a")
        XCTAssertEqual(effectiveSelection("b", among: ["a", "b"]), "b")
        XCTAssertNil(effectiveSelection("b", among: [String]()))
    }

    // 70
    func testCountsAreInflected() {
        XCTAssertEqual(counted(1, "item"), "1 item")
        XCTAssertEqual(counted(0, "item"), "0 items")
        XCTAssertEqual(counted(2, "model"), "2 models")
    }

    // 71
    func testDataDatesAreFormattedLikeTheRestOfTheApp() {
        XCTAssertEqual(displayDate("2026-09-30"), Format.date.string(from: Dates.parse("2026-09-30")!))
        XCTAssertEqual(displayDate("2026-10-19T06:12:00Z"), Format.date.string(from: Dates.parse("2026-10-19")!))
        XCTAssertEqual(displayDate(nil), "?")
    }

    // 68 and the rename
    func testPageNamesOldAndNew() {
        XCTAssertEqual(Page.trends.rawValue, "Trends")
        XCTAssertEqual(Page(stored: "Direction Trends"), .trends, "a page saved by an older version still opens")
        XCTAssertEqual(Page(stored: "Latest Advances"), .advances)
        XCTAssertEqual(Page(stored: "advances"), .advances)
        XCTAssertNil(Page(stored: "Nope"))
    }

    // 67
    func testComparisonUsesBenchmarksAtLeastTwoModelsShare() throws {
        let data = try XCTUnwrap(SnapshotTests.data)
        let profiles = Analysis.profiles(data).sorted { $0.scores.count > $1.scores.count }
        let picked = Array(profiles.prefix(3))
        let shared = ModelComparison.sharedBenchmarks(picked, infos: data.benchmarks)
        XCTAssertFalse(shared.isEmpty)
        XCTAssertLessThanOrEqual(shared.count, 12)
        for b in shared { XCTAssertGreaterThanOrEqual(picked.filter { $0.score(b) != nil }.count, 2) }
        let superseded = Set(data.benchmarks.filter { $0.supersededBy != nil }.map(\.name))
        XCTAssertTrue(superseded.isDisjoint(with: shared))
    }
}

/// Renders the new views, to catch crashes and (with RENDER_APP=<folder>) for visual review.
@MainActor
final class AppRenderTests: XCTestCase {
    func testRenderNewViews() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppRender-\(UUID().uuidString)", isDirectory: true)
        let suite = DataStoreTests.suite
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defer {
            try? FileManager.default.removeItem(at: dir)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        let store = DataStore(storageDir: dir, defaults: UserDefaults(suiteName: suite)!, network: .offline)
        await store.reload()
        let data = store.data
        let picked = Array(store.profiles.sorted { $0.scores.count > $1.scores.count }.prefix(3))
        let views: [(String, AnyView)] = [
            ("Banner", AnyView(StatusBanner().frame(width: 1000))),
            ("Comparison", AnyView(ModelComparison(models: picked, infos: data.benchmarks) {}.frame(width: 520))),
            ("Detail", AnyView(ModelDetail(profile: picked[0], infos: data.benchmarks).frame(width: 460))),
            ("Trends", AnyView(TrendsView().frame(width: 1200))),
            ("Capabilities", AnyView(CapabilitiesView().frame(width: 1200))),
            ("Advances", AnyView(AdvancesView().frame(width: 1200))),
        ]
        let out = ProcessInfo.processInfo.environment["RENDER_APP"].map { URL(fileURLWithPath: $0) }
        for (name, view) in views {
            let renderer = ImageRenderer(content: view.environment(store).padding(24).background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage, name)
            XCTAssertGreaterThan(image.size.height, 20, name)
            if let out {
                let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
            }
        }
    }
}
