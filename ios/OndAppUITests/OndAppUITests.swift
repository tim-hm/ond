import XCTest

@MainActor
final class OndAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testHomeMeetsTheSystemAccessibilityAudit() throws {
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        for tab in ["Home", "Protocols", "Exercises", "Progress", "Coach"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "the \(tab) tab should stay visible")
        }

        XCTAssertTrue(app.buttons["suggested-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["practice-rhythm-card"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["last-session-card"].exists)
        XCTAssertTrue(app.buttons["repeat-card"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["practice-summary"].exists)
        XCTAssertFalse(app.buttons["leaderboards-door"].exists)

        try app.performAccessibilityAudit { issue in
            // iOS 26 deliberately scrolls content under its translucent,
            // floating tab bar. Contrast there belongs to the system chrome;
            // every app-owned element outside that overlap still has to pass.
            guard issue.auditType == .contrast,
                  let element = issue.element
            else { return false }

            return element.frame.intersects(self.app.tabBars.firstMatch.frame)
        }
    }

    func testProgressOwnsPracticeReflectionAndMeetsTheAccessibilityAudit() throws {
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Progress"].tap()

        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["practice-summary"].exists)
        XCTAssertTrue(app.buttons["leaderboards-door"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["practice-chart"].exists)
        XCTAssertTrue(app.staticTexts["Sessions"].exists)

        try app.performAccessibilityAudit { issue in
            guard issue.auditType == .contrast,
                  let element = issue.element
            else { return false }

            return element.frame.intersects(self.app.tabBars.firstMatch.frame)
        }
    }

    func testActiveSessionExposesItsControlsAndMeetsTheAccessibilityAudit() throws {
        app.tabBars.buttons["Exercises"].tap()

        let exercise = app.staticTexts["Coherent Breathing"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 10))
        exercise.tap()

        let begin = app.buttons["Begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()

        let checkIn = app.buttons["Check in"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 2))
        checkIn.tap()

        XCTAssertTrue(app.staticTexts["How do you feel right now?"].waitForExistence(timeout: 2))
        for answer in ["Not good", "Okay", "Good"] {
            XCTAssertTrue(app.buttons[answer].exists)
        }
        XCTAssertFalse(
            app.staticTexts["Optional. Saved to Health on this phone; önd never sees it."].exists
        )
        XCTAssertFalse(app.buttons["Cancel"].exists)

        let pause = app.buttons["Pause"]
        XCTAssertFalse(
            pause.waitForExistence(timeout: 4),
            "the exercise must not start while the optional check-in is open"
        )

        app.buttons["Not now"].tap()
        XCTAssertFalse(checkIn.exists, "the restarted countdown must not offer the check-in twice")

        XCTAssertTrue(pause.waitForExistence(timeout: 6))
        XCTAssertTrue(pause.isHittable)

        let end = app.buttons["End"]
        XCTAssertTrue(end.exists)
        XCTAssertTrue(end.isHittable)
        try app.performAccessibilityAudit()
    }

    func testExerciseDetailKeepsActionsInTheReadingFlow() throws {
        app.tabBars.buttons["Exercises"].tap()

        let exercise = app.staticTexts["Box Breathing"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 10))
        exercise.tap()

        XCTAssertTrue(app.staticTexts["19 cycles, about 5 minutes."].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "However many you do")
            ).count,
            0
        )

        let begin = app.buttons["Begin"]
        XCTAssertTrue(begin.exists)
        XCTAssertTrue(begin.isHittable)
        XCTAssertGreaterThanOrEqual(begin.frame.height, 44)
        XCTAssertTrue(app.staticTexts["About this exercise"].exists)
        XCTAssertTrue(app.staticTexts["How it works"].exists)
        XCTAssertTrue(app.staticTexts["Evidence"].exists)

        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }

            if issue.auditType == .contrast || issue.auditType == .textClipped,
               element.frame.intersects(self.app.tabBars.firstMatch.frame)
            {
                return true
            }

            // iOS 26 compares the chart labels' unrotated bounds, reporting
            // scaled, visibly complete labels as partially scaled or clipped.
            if issue.auditType == .dynamicType || issue.auditType == .textClipped,
               element.label.contains(" · ")
            {
                return true
            }

            return false
        }

        let coach = app.buttons["Ask the coach about Box Breathing"]
        for _ in 0 ..< 3 where !coach.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(coach.isHittable)
        XCTAssertGreaterThanOrEqual(coach.frame.height, 44)
        XCTAssertFalse(begin.isHittable, "Begin should scroll with the practice content")
        XCTAssertGreaterThan(coach.frame.minY, app.staticTexts["Evidence"].frame.minY)
    }

    func testBasicsLeadsWithPracticeAndMeetsTheAccessibilityAudit() throws {
        app.tabBars.buttons["Coach"].tap()

        let basics = app.buttons["The basics"]
        XCTAssertTrue(basics.waitForExistence(timeout: 10))
        basics.tap()

        let lead = app.staticTexts["Practice matters more than perfect"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        XCTAssertTrue(lead.isHittable, "the practice-first message should appear without scrolling")

        try app.performAccessibilityAudit { issue in
            guard issue.auditType == .contrast,
                  let element = issue.element
            else { return false }

            return element.frame.intersects(self.app.tabBars.firstMatch.frame)
        }
    }
}
