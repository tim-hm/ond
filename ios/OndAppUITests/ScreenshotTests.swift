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
        // The tab bar arrives before the app is done seeding six weeks of
        // history, and a tab tapped while that is running is swallowed. Home's
        // own content is the readiness signal — waiting for it here is what
        // stops the first navigation being the one that fails.
        XCTAssertTrue(
            app.buttons["suggested-card"].waitForExistence(timeout: arrival),
            "Home should finish loading before anything is navigated"
        )

        // Before Home, because Home's Starred section is empty until something
        // is starred — and an empty half-screen is the weakest thing a listing
        // can lead with. Starred through the control rather than seeded, so the
        // shot is of the state a person would actually produce.
        starProtocols()

        go(to: "Home")
        capture("02-home", once: app.buttons["suggested-card"])

        for (name, tab) in [("04-exercises", "Exercises"), ("05-progress", "Progress")] {
            go(to: tab)
            capture(name, once: app.staticTexts[tab])
        }

        captureTechniqueDetail()
        captureSession()
    }

    /// Switches tab and waits for it, retrying the tap.
    ///
    /// A tap that lands while the previous transition is still animating does
    /// nothing and reports nothing, so a single tap-then-wait is flaky in a way
    /// that looks like the screen being slow. Every tab here titles itself with
    /// its own name, which is what arrival is judged on.
    private func go(to tab: String) {
        let button = app.tabBars.buttons[tab]
        let title = app.staticTexts[tab]

        for _ in 0 ..< 3 {
            if title.exists {
                return
            }
            if button.isHittable {
                button.tap()
            }
            if title.waitForExistence(timeout: 8) {
                return
            }
        }

        XCTFail("the \(tab) tab never arrived")
    }

    /// Stars the first few protocols and captures the tab while it is there.
    ///
    /// By label rather than by title: `StopStarButton` labels itself
    /// "Star <title>", so this survives the protocols being renamed or reordered,
    /// which hardcoding two names would not.
    private func starProtocols() {
        go(to: "Protocols")

        // Up to three, because Home does not repeat itself: whichever protocol
        // it is suggesting today is left out of Starred, so starring exactly two
        // leaves a single row there on any day the suggestion is one of them.
        //
        // Tolerant of finding fewer, because how many are reachable without
        // scrolling is a layout question and this is not the test that should
        // fail over it — two is what the shot needs, and the third is a bonus.
        //
        // Re-queried each time: starring rewrites the button's label to
        // "Unstar …", so the match set shifts under a held index.
        var starred = 0
        while starred < 3 {
            let star = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Star ")
            ).firstMatch

            guard star.waitForExistence(timeout: 5), star.isHittable else { break }
            star.tap()
            starred += 1
        }

        XCTAssertGreaterThanOrEqual(
            starred, 2,
            "Home's Starred section needs at least two protocols behind it"
        )

        capture("03-protocols", once: app.staticTexts["Protocols"])
    }

    /// The evidence copy on one technique — the listing claims the app presents
    /// research with its limits, and this is the screen that shows it.
    private func captureTechniqueDetail() {
        go(to: "Exercises")

        let first = app.cells.firstMatch
        guard first.waitForExistence(timeout: 10) else {
            return XCTFail("the Exercises tab should list at least one technique")
        }

        first.tap()
        capture("06-technique", once: app.buttons["Close"], or: app.navigationBars.firstMatch)
    }

    /// A session in progress, shot last because starting one leaves the tabs.
    private func captureSession() {
        go(to: "Home")

        let suggested = app.buttons["suggested-card"]
        guard suggested.waitForExistence(timeout: 10) else {
            return XCTFail("Home should offer a session to start")
        }

        // The session's own End control is the signal that one actually opened.
        // Neither the breath figure nor the tab bar's absence will do: Home's
        // cards draw a figure of their own, and the tab bar stays in the tree
        // behind the cover — between them those two cost two runs, one of which
        // passed while photographing Home and calling it a session.
        let end = app.buttons["End"]

        for attempt in 0 ..< 2 where !end.exists {
            // Tapping into a tab switch that is still animating does nothing at
            // all, silently, which is what the second attempt is for.
            if suggested.isHittable {
                suggested.tap()
            }
            _ = end.waitForExistence(timeout: 15)
            if attempt == 1, !end.exists {
                print("SCREENSHOTS: no session opened. Screen was:")
                print(app.debugDescription)
            }
        }

        guard end.exists else {
            return XCTFail("tapping the suggested card should open a session")
        }

        // Any of the three guide shapes; which one depends on the technique the
        // fixture put in front of today. Scoped to `otherElements` rather than
        // `descendants(matching: .any)`, which re-snapshots the whole
        // accessibility tree on every poll while the element is absent.
        let guide = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "breath-guide-")
        ).firstMatch

        guard guide.waitForExistence(timeout: 20) else {
            return XCTFail("a session should draw a breath guide")
        }

        // The badge needs one reading and the curve needs several, and the
        // rehearsal sends at `PulseRelay.spacing` — the real wrist's eight
        // seconds — so three points is around twenty. Waiting is the whole
        // reason: capturing the moment the guide appears photographs a session
        // whose heart rate has not started, which is the empty state.
        // `PulseBadge` combines its children, so the rate is the element's
        // *value* and "Heart rate" is the label — matching on the number would
        // match nothing.
        let badge = app.otherElements["Heart rate"]
        if badge.waitForExistence(timeout: 15) {
            // Let the curve fill in behind the badge before capturing.
            Thread.sleep(forTimeInterval: 20)
        } else {
            // Not a failure: a session without a heart rate is a real state —
            // it is what every phone with no watch shows — so the set is still
            // worth having. The tree says why, for whoever looks next.
            print("SCREENSHOTS: no heart rate arrived. Session screen was:")
            print(app.debugDescription)
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
