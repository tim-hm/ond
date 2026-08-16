import XCTest

/// Captures the two screens that ask for money.
///
/// Separate from `ScreenshotTests` because each needs its own launch: one opens
/// first run on the trial step, the other opens the paywall over Home, and both
/// need the free tier so the offer is drawn at all. `ScreenshotTests` launches
/// once, subscribed, and walks — three incompatible things to ask of one
/// `setUp`.
///
/// These are not listing shots. They are what App Store Connect asks for as a
/// subscription's review screenshot, and what a change to either surface should
/// be checked against — which is exactly why they belong in the harness rather
/// than in whoever last took one by hand.
///
/// **Not part of `test:swift` or the gate**, for `ScreenshotTests`' reason.
/// `mise run ios:screenshots` names this class too.
@MainActor
final class SubscriptionScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// The offer as somebody meets it on the way in: one price, and "See plans"
    /// for anybody who wants the year.
    func testCaptureTheFirstRunOffer() {
        launch(with: ["--ui-testing-onboarding-trial"])

        // The headline names the trial only when the App Store answered with
        // one, so the plain title is the fallback rather than a second failure:
        // a run against a simulator whose StoreKit configuration did not load
        // should say so by looking wrong, not by timing out here.
        capture(
            "07-subscription-first-run",
            once: app.staticTexts["önd+, free for 7 days"],
            or: app.staticTexts["önd+"]
        )
    }

    /// Both cadences, which is the frame that shows a reviewer what is sold and
    /// at what price.
    func testCaptureThePlanPicker() {
        launch(with: ["--ui-testing-paywall"])

        capture(
            "08-subscription-plans",
            once: app.staticTexts["More from your practice"]
        )
    }

    /// Launches at the free tier, which is what makes either screen appear.
    ///
    /// `-plus.tier 0` rather than trusting the default: the simulator carries a
    /// StoreKit purchase between runs, and a paywall photographed after
    /// somebody bought önd+ on it is a blank screen that dismissed itself.
    private func launch(with arguments: [String]) {
        app.launchArguments = ["--ui-testing", "-plus.tier", "0"] + arguments
        app.launch()
    }
}
