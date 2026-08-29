import XCTest

/// Captures the two screens that ask for money in both appearances.
/// Separate from `ScreenshotTests` because each needs its own free-tier
/// launch, where that class launches once, subscribed, and walks. Not listing
/// shots: they are App Store Connect's subscription review screenshots.
/// **Not part of `test:swift` or the gate** — `mise run ios:screenshots` runs it.
@MainActor
final class SubscriptionScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// The complete offer as somebody meets it on the way in.
    func testCaptureTheFirstRunOffer() {
        launch(with: ["--ui-testing-onboarding-trial"], appearance: .light)

        capture(
            "07-subscription-first-run",
            once: app.staticTexts["Everything that works offline stays free. Forever."]
        )
    }

    /// Both cadences, which is the frame that shows a reviewer what is sold and
    /// at what price.
    func testCaptureThePlanPicker() {
        launch(with: ["--ui-testing-paywall"], appearance: .light)

        capture(
            "08-subscription-plans",
            once: app.staticTexts["Everything that works offline stays free. Forever."]
        )
    }

    /// The first-run offer with the system dark appearance applied.
    func testCaptureTheFirstRunOfferInDarkMode() {
        launch(with: ["--ui-testing-onboarding-trial"], appearance: .dark)

        capture(
            "09-subscription-first-run-dark",
            once: app.staticTexts["Everything that works offline stays free. Forever."]
        )
    }

    /// The standalone plan picker with the system dark appearance applied.
    func testCaptureThePlanPickerInDarkMode() {
        launch(with: ["--ui-testing-paywall"], appearance: .dark)

        capture(
            "10-subscription-plans-dark",
            once: app.staticTexts["Everything that works offline stays free. Forever."]
        )
    }

    /// Launches at the free tier, which is what makes either screen appear.
    ///
    /// `-plus.tier 0` rather than trusting the default: the simulator carries a
    /// StoreKit purchase between runs, and a paywall photographed after
    /// somebody bought önd+ on it is a blank screen that dismissed itself.
    private func launch(with arguments: [String], appearance: Appearance) {
        app.launchArguments = [
            "--ui-testing",
            "-plus.tier",
            "0",
            "-app.appearance",
            appearance.rawValue,
        ] + arguments
        app.launch()
    }

    private enum Appearance: String {
        case light
        case dark
    }
}
