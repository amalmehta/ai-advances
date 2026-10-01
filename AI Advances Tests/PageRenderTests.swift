import XCTest
import SwiftUI
@testable import AI_Advances

/// Renders whole pages (including what's below the fold) to PNGs for visual review.
/// Off by default; run with TEST_RUNNER_RENDER_PAGES=<output folder>.
@MainActor
final class PageRenderTests: XCTestCase {
    func testRenderPages() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_PAGES"] else { throw XCTSkip("Set RENDER_PAGES to render") }
        let store = DataStore()
        await store.reload()
        let pages: [(String, AnyView)] = [("Forecasts", AnyView(ForecastsView())), ("Labs", AnyView(LabsView()))]
        for (name, view) in pages {
            let renderer = ImageRenderer(content: view.environment(store).padding(24).frame(width: 1200).background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name).png"))
        }
    }
}
