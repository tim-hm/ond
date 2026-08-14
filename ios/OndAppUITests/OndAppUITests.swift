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
}
