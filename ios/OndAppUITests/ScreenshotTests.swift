import XCTest

/// Captures the App Store screenshot set, one attachment per shot.
///
/// A test rather than a person with a simulator and a keyboard, for the reason
/// any fixture is written down: the set has to be retaken every time a screen
/// moves, and a process that depends on remembering which six screens were shot
/// last time, in which order, with which content, produces a different set each
/// time. Here the answer is in one file and the whole set regenerates in a
/// command.
///
/// **Not part of `test:swift` or the gate.** It is driven by
/// `mise run ios:screenshots`, which boots the one device size App Store Connect
/// requires, freezes the status bar and exports the attachments. Left in the
/// ordinary suite it would add a minute to every run to assert almost nothing —
/// what it checks is that each screen can be reached and is not empty, which the
/// other UI tests already cover better.
///
/// Attachment names are the exported filenames, so they carry the order the
/// listing wants rather than the order that is convenient to walk: the session
/// is shot last, because starting one changes state, and is named first,
/// because it is what the app is.
@MainActor
final class ScreenshotTests: XCTestCase {
    /// Long enough for a cold launch that also seeds six weeks of history.
    private let arrival: TimeInterval = 30

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            // The history behind Home and Progress. Without it both screens are
            // honest and useless — a streak of zero and an empty journal.
            "--ui-testing-demo",
            // Plus, so the trends and leaderboards render rather than showing
            // their paywall. This is a choice worth revisiting per shot: a
            // screenshot of a paid screen is allowed and ordinary, but it is
            // also the first thing a free user will not find.
            "-plus.tier", "1",
        ]
        app.launch()
    }

    func testCaptureTheListingSet() {
        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(
            home.waitForExistence(timeout: arrival),
            "the app should reach Home before anything is captured"
        )

        capture("02-home", once: app.buttons["suggested-card"])

        for (name, tab, anchor) in [
            ("03-protocols", "Protocols", "Protocols"),
            ("04-exercises", "Exercises", "Exercises"),
            ("05-progress", "Progress", "Sessions"),
        ] {
            app.tabBars.buttons[tab].tap()
            capture(name, once: app.staticTexts[anchor])
        }

        captureTechniqueDetail()
        captureSession(from: home)
    }

    /// The evidence copy on one technique — the listing claims the app presents
    /// research with its limits, and this is the screen that shows it.
    private func captureTechniqueDetail() {
        app.tabBars.buttons["Exercises"].tap()

        let first = app.cells.firstMatch
        guard first.waitForExistence(timeout: 10) else {
            return XCTFail("the Exercises tab should list at least one technique")
        }

        first.tap()
        capture("06-technique", once: app.buttons["Close"], or: app.navigationBars.firstMatch)
    }

    /// A session in progress, shot last because starting one leaves the tabs.
    private func captureSession(from home: XCUIElement) {
        home.tap()

        let suggested = app.buttons["suggested-card"]
        guard suggested.waitForExistence(timeout: 10) else {
            return XCTFail("Home should offer a session to start")
        }

        suggested.tap()

        // Any of the three guide shapes means a session is running; which one
        // depends on the technique the fixture put in front of today.
        let guide = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "breath-guide-")
        ).firstMatch

        guard guide.waitForExistence(timeout: 20) else {
            return XCTFail("tapping the suggested card should start a session")
        }

        capture("01-session", once: guide)
    }

    /// Waits for a screen to have arrived, then attaches the whole screen.
    ///
    /// The anchor is the point: a screenshot harness that captures on a timer
    /// eventually ships a shot of a spinner, and nothing about the resulting
    /// PNG says it went wrong.
    private func capture(
        _ name: String,
        once anchor: XCUIElement,
        or fallback: XCUIElement? = nil
    ) {
        if !anchor.waitForExistence(timeout: 15) {
            guard let fallback, fallback.waitForExistence(timeout: 5) else {
                return XCTFail("\(name): the screen never arrived, so nothing was captured")
            }
        }

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        // Attachments are discarded on success by default, and every run of
        // this test is a success.
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
