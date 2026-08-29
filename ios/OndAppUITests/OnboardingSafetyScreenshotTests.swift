import XCTest

/// Captures the safety wall in both appearances. The screen's fidelity lives
/// in wrapping and vertical rhythm, which an existence assertion cannot
/// protect; a direct route avoids the Health and notification prompts that
/// precede it in first run. **Not part of `test:swift` or the gate** —
/// `mise run ios:screenshots` drives this class on the fixed device.
@MainActor
final class OnboardingSafetyScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testCaptureTheSafetyWall() {
        launch(appearance: .light)
        capture("11-onboarding-safety", once: app.staticTexts["Before you start"])
    }

    func testCaptureTheSafetyWallInDarkMode() {
        launch(appearance: .dark)
        capture("12-onboarding-safety-dark", once: app.staticTexts["Before you start"])
    }

    private func launch(appearance: Appearance) {
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-onboarding-safety",
            "-app.appearance",
            appearance.rawValue,
        ]
        app.launch()
    }

    private enum Appearance: String {
        case light
        case dark
    }
}
