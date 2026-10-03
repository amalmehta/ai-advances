import XCTest

/// Runs Xcode's accessibility audit (VoiceOver descriptions, contrast, hit areas…) on every page.
/// Run it with the "Accessibility Audit" scheme; it drives the real app, so keep the window
/// unobstructed while it runs.
final class AccessibilityAuditTests: XCTestCase {
    static let pages = ProcessInfo.processInfo.environment["AUDIT_PAGES"]?.components(separatedBy: ",")
        ?? ["Direction Trends", "Forecasts", "Labs", "Latest Advances", "Capabilities",
            "Models", "Cost", "Context & Modalities", "Compute"]

    override func setUp() { continueAfterFailure = true }

    /// Issues that belong to macOS rather than this app's content, or that come from the test
    /// environment (contrast sampled through another window covering ours).
    static func isNoise(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let e = issue.element else { return true }
        switch e.elementType {
        case .touchBar: return true
        case .popUpButton where issue.auditType == .action: return true            // SwiftUI menu picker
        case .group where !e.isEnabled: return true                                 // window and split-view containers
        default: break
        }
        if issue.auditType == .parentChild { return true }                          // window chrome
        if issue.auditType == .contrast && !e.isHittable { return true }            // covered by another window
        return false
    }

    @MainActor
    func testEveryPagePassesTheAccessibilityAudit() throws {
        for page in Self.pages {
            let app = XCUIApplication()
            app.launchArguments = ["-page", page, "-ApplePersistenceIgnoreState", "YES"]
            app.launch()
            app.activate()
            XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 45), "\(page) didn't load")
            sleep(3) // let charts and the background forecast work finish
            XCTContext.runActivity(named: page) { _ in
                do {
                    try app.performAccessibilityAudit { issue in
                        if Self.isNoise(issue) { return true }
                        let e = issue.element
                        print("AUDIT [\(page)] \(issue.compactDescription) | \(e?.elementType.rawValue ?? 0) | \(e?.label ?? "") \((e?.value as? String) ?? "")")
                        return false
                    }
                } catch {
                    XCTFail("\(page): \(error)")
                }
            }
            app.terminate()
        }
    }
}
