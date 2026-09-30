import SwiftUI
import Charts
import AppKit

/// Chart colors: the validated categorical palette, stepped separately for light and dark.
enum Palette {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                           green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }

    static let series: [Color] = [
        dynamic(0x2a78d6, 0x3987e5), // blue
        dynamic(0xeb6834, 0xd95926), // orange
        dynamic(0x1baf7a, 0x199e70), // aqua
        dynamic(0xeda100, 0xc98500), // yellow
        dynamic(0xe87ba4, 0xd55181), // magenta
        dynamic(0x008300, 0x008300), // green
        dynamic(0x4a3aa7, 0x9085e9), // violet
        dynamic(0xe34948, 0xe66767), // red
    ]
    static let muted = dynamic(0x898781, 0x898781)
    static let grid = dynamic(0xe1e0d9, 0x2c2c2a)
    static let surface = dynamic(0xfcfcfb, 0x1a1a19)

    static func color(_ i: Int) -> Color { series[i % series.count] }
}

struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.grid))
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let detail: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.grid))
    }
}

struct Tooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(lines, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.grid))
    }
}

/// Finds the plotted point nearest the pointer, for hover tooltips on scatter and line charts.
struct HoverLayer<ID: Hashable>: View {
    let proxy: ChartProxy
    let points: [(id: ID, x: Date, y: Double)]
    @Binding var selection: ID?
    var radius: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let loc) = phase, let plot = proxy.plotFrame else { selection = nil; return }
                    let origin = geo[plot].origin
                    let p = CGPoint(x: loc.x - origin.x, y: loc.y - origin.y)
                    var best: (ID, CGFloat)?
                    for pt in points {
                        guard let px = proxy.position(forX: pt.x), let py = proxy.position(forY: pt.y) else { continue }
                        let d = hypot(px - p.x, py - p.y)
                        if d < (best?.1 ?? radius) { best = (pt.id, d) }
                    }
                    selection = best?.0
                }
        }
    }
}

struct PageHeader: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(summary).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Footnote: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// Recessive axes and gridlines shared by every chart.
    func quietAxes() -> some View {
        self
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisTick().foregroundStyle(Palette.grid)
                    AxisValueLabel().foregroundStyle(Palette.muted)
                }
            }
    }
}

func yearsAgo(_ n: Double, from now: Date = Date()) -> Date {
    now.addingTimeInterval(-n * 365.25 * 86_400)
}

/// Legend entry: the swatch carries the color, the text stays in normal ink.
struct LegendItem: View {
    let label: String
    let color: Color
    var line = false

    var body: some View {
        HStack(spacing: 5) {
            if line { Capsule().fill(color).frame(width: 14, height: 2.5) }
            else { Circle().fill(color).frame(width: 8, height: 8) }
            Text(label).foregroundStyle(.secondary)
        }
    }
}
