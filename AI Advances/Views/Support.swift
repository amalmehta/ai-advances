import SwiftUI
import Accessibility

/// "1 item", "2 items", "1 day".
func counted(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(n) \(n == 1 ? singular : plural ?? singular + "s")"
}

/// A "yyyy-MM-dd…" string from the data files, shown like every other date in the app.
func displayDate(_ iso: String?) -> String {
    guard let iso else { return "?" }
    return Dates.parse(iso).map { Format.date.string(from: $0) } ?? iso
}

/// What a picker should show when its saved choice isn't among the options (yet, or any more):
/// the saved choice if it's there, else the first option.
func effectiveSelection<T: Equatable>(_ saved: T, among options: [T]) -> T? {
    options.contains(saved) ? saved : options.first
}

extension View {
    /// Keeps a picker's stored selection pointing at a real option: whenever the options change
    /// (or on first appearance), writes the effective selection back.
    func keepSelection<T: Equatable>(_ saved: Binding<T>, among options: [T]) -> some View {
        onChange(of: options, initial: true) { _, options in
            if let e = effectiveSelection(saved.wrappedValue, among: options), e != saved.wrappedValue { saved.wrappedValue = e }
        }
    }
}

// MARK: Accessible chart data

/// The data behind a scatter or line chart, for VoiceOver's chart rotor and Audio Graphs.
struct ChartData: AXChartDescriptorRepresentable {
    enum Axis {
        case date(String)
        case number(String, log: Bool = false, format: (Double) -> String)
    }

    struct Point {
        let x: Double
        let y: Double
        let label: String?
    }

    struct Series {
        let name: String
        let continuous: Bool
        let points: [Point]
    }

    let title: String
    let summary: String
    let x: Axis
    let y: Axis
    let series: [Series]

    /// Converts a date to the x value used for `.date` axes.
    static func x(_ d: Date) -> Double { d.timeIntervalSince1970 }

    func makeChartDescriptor() -> AXChartDescriptor {
        AXChartDescriptor(
            title: title, summary: summary,
            xAxis: axis(x, values: series.flatMap { $0.points.map(\.x) }),
            yAxis: axis(y, values: series.flatMap { $0.points.map(\.y) }),
            additionalAxes: [],
            series: series.map { s in
                AXDataSeriesDescriptor(name: s.name, isContinuous: s.continuous,
                                       dataPoints: s.points.map { AXDataPoint(x: $0.x, y: $0.y, additionalValues: [], label: $0.label) })
            })
    }

    private func axis(_ a: Axis, values: [Double]) -> AXNumericDataAxisDescriptor {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let range = lo...(hi > lo ? hi : lo + 1)
        switch a {
        case .date(let title):
            return AXNumericDataAxisDescriptor(title: title, range: range, gridlinePositions: []) {
                Format.date.string(from: Date(timeIntervalSince1970: $0))
            }
        case .number(let title, let log, let format):
            let d = AXNumericDataAxisDescriptor(title: title, range: range, gridlinePositions: []) { format($0) }
            if log { d.scaleType = .log10 }
            return d
        }
    }
}
