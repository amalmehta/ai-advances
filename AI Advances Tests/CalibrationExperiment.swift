import XCTest
@testable import AI_Advances

/// Sweeps the range width and scores reconstructed forecasts at each, overall and with each
/// milestone held out. Prints a table; run on demand with TEST_RUNNER_CALIBRATE=1.
final class CalibrationExperiment: XCTestCase {
    func testSweep() throws {
        guard ProcessInfo.processInfo.environment["CALIBRATE"] != nil else { throw XCTSkip("Set CALIBRATE to run") }
        let data = SnapshotTests.data!
        let now = Dates.parse("2026-09-30")!
        let saved = Forecasts.rangeZ
        defer { Forecasts.rangeZ = saved }
        var rows: [(z: Double, items: [TrackRecord.Item])] = []
        for z in stride(from: 1.0, through: 6.0, by: 0.25) {
            Forecasts.rangeZ = z
            let current = Forecasts.all(data, profiles: Analysis.profiles(data), asOf: now)
            let history = Forecasts.reconstructed(data, now: now, months: 18)
            // Every scored forecast, not just one per milestone.
            var all: [TrackRecord.Item] = []
            for f in current where f.reached != nil {
                all += TrackRecord.score(history: history, current: [f]).allItems
            }
            rows.append((z, all))
            let cov = Double(all.filter(\.inside).count) / Double(max(1, all.count))
            let width = all.compactMap { i in i.late.map { Dates.months(from: i.early ?? i.predicted, to: $0) } }.sorted()
            print(String(format: "CAL z=%.2f coverage %.0f%% (%d/%d) median range width %.0f months", z, cov * 100,
                         all.filter(\.inside).count, all.count, width.isEmpty ? 0 : width[width.count / 2]))
        }
        // Leave one milestone out: pick the smallest z reaching 80% on the others, test on the one left out.
        let milestones = Set(rows[0].items.map(\.forecastID))
        var heldIn = 0, heldTotal = 0
        for m in milestones.sorted() {
            let pick = rows.first { r in
                let others = r.items.filter { $0.forecastID != m }
                return Double(others.filter(\.inside).count) / Double(max(1, others.count)) >= 0.8
            } ?? rows.last!
            let test = pick.items.filter { $0.forecastID == m }
            heldIn += test.filter(\.inside).count; heldTotal += test.count
            print(String(format: "CAL held out %@: chose z=%.2f, %d/%d inside", m, pick.z, test.filter(\.inside).count, test.count))
        }
        print(String(format: "CAL leave-one-milestone-out coverage: %.0f%% (%d/%d)", Double(heldIn) / Double(max(1, heldTotal)) * 100, heldIn, heldTotal))
    }
}
