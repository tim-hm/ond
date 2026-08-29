import XCTest

/// Captures the App Store screenshot set, one attachment per shot, so the
/// whole set regenerates in one command instead of from memory. **Not part
/// of `test:swift` or the gate** — `mise run ios:screenshots` boots the one
/// required device size, freezes the status bar and exports the attachments.
/// Names carry the listing's order: the session shoots last but names first.
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
            app.buttons["home-breathe"].waitForExistence(timeout: arrival),
            "Home should finish loading before anything is navigated"
        )

        // Starred through the control rather than seeded, so the Moments
        // shot is of the state a person would actually produce.
        starMoments()

        go(to: "Home")
        capture("02-home", once: app.buttons["home-breathe"])
        captureChoiceSheet()

        for (name, tab) in [("04-exercises", "Exercises"), ("05-progress", "Progress")] {
            go(to: tab)
            capture(name, once: app.staticTexts[tab])
        }

        captureTechniqueDetail()
        captureSession()
    }

    /// Switches tab and waits for it, retrying the tap. A tap that lands
    /// while the previous transition is still animating does nothing and
    /// reports nothing, so a single tap-then-wait is flaky in a way that
    /// looks like the screen being slow. Four tabs title themselves; Home
    /// announces arrival with its Breathe button instead.
    private func go(to tab: String) {
        let button = app.tabBars.buttons[tab]
        let arrival = tab == "Home" ? app.buttons["home-breathe"] : app.staticTexts[tab]

        for _ in 0 ..< 3 {
            if arrival.exists {
                return
            }
            if button.isHittable {
                button.tap()
            }
            if arrival.waitForExistence(timeout: 8) {
                return
            }
        }

        XCTFail("the \(tab) tab never arrived")
    }

    /// Stars the first few moments and captures the tab while it is there.
    ///
    /// By label rather than by title: `StopStarButton` labels itself
    /// "Star <title>", so this survives the moments being renamed or reordered,
    /// which hardcoding two names would not.
    private func starMoments() {
        go(to: "Moments")

        // Up to three, tolerant of fewer: two filled stars is what the shot
        // needs, and how many are reachable without scrolling is a layout
        // question. Re-queried each time: starring rewrites the label to
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
            "the Moments shot needs at least two filled stars"
        )

        capture("03-moments", once: app.staticTexts["Moments"])
    }

    /// The evidence copy on one technique — the listing claims the app presents
    /// research with its limits, and this is the screen that shows it.
    /// The sheet under Home's line — the one place the app asks what to
    /// breathe, so the listing set shows that it exists and how little of it
    /// there is.
    private func captureChoiceSheet() {
        app.buttons["home-start-with"].tap()
        capture("02b-home-sheet", once: app.buttons["all-exercises-row"])

        // Left by its own door rather than by a swipe: the door dismisses the
        // sheet and lands on Exercises, which is where the set goes next, and
        // a swipe that misses leaves the sheet over the tab bar for the rest
        // of the run.
        app.buttons["all-exercises-row"].tap()
        XCTAssertTrue(app.staticTexts["Exercises"].waitForExistence(timeout: 10))
    }

    private func captureTechniqueDetail() {
        go(to: "Exercises")

        let first = app.staticTexts["Box Breathing"]
        guard first.waitForExistence(timeout: 10) else {
            return XCTFail("the Exercises tab should list at least one technique")
        }

        first.tap()
        capture("06-technique", once: app.buttons["Close"], or: app.navigationBars.firstMatch)
    }

    /// A session in progress, shot last because starting one leaves the tabs.
    private func captureSession() {
        go(to: "Home")

        let lead = app.buttons["home-breathe"]
        guard lead.waitForExistence(timeout: 10) else {
            return XCTFail("Home should offer a session to start")
        }

        // The session's own End control is the signal that one actually opened.
        // Neither the breath figure nor the tab bar's absence will do: Home's
        // cards draw a figure of their own, and the tab bar stays in the tree
        // behind the cover — between them those two cost two runs, one of which
        // passed while photographing Home and calling it a session.
        let end = app.buttons["End session"]

        for attempt in 0 ..< 2 where !end.exists {
            // Tapping into a tab switch that is still animating does nothing at
            // all, silently, which is what the second attempt is for.
            if lead.isHittable {
                lead.tap()
            }
            acceptTechniqueWarning()
            _ = end.waitForExistence(timeout: 15)
            if attempt == 1, !end.exists {
                print("SCREENSHOTS: no session opened. Screen was:")
                print(app.debugDescription)
            }
        }

        guard end.exists else {
            return XCTFail("tapping Breathe should open a session")
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

        // The rehearsal sends at `PulseRelay.spacing` — the real wrist's
        // eight seconds — so the curve's three points take around twenty.
        // Capturing when the guide appears photographs the empty state.
        // `PulseBadge` combines its children: the rate is the element's
        // *value* and "Heart rate" the label — the number matches nothing.
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

    /// Clears the safety interstitial the riskier techniques put in front of
    /// a first session. Which technique Home suggests depends on the day and
    /// only some are gated, so without this the capture fails on those days
    /// only, timing out on an End control behind `TechniqueWarningView`.
    /// Silently absent is the ordinary case: ungated, or already accepted.
    private func acceptTechniqueWarning() {
        let understood = app.buttons["I understand"]

        guard understood.waitForExistence(timeout: 5), understood.isHittable else {
            return
        }

        understood.tap()
    }
}
