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

        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) {
            skip.tap()
        }

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 12))
        XCTAssertTrue(pause.isHittable)

        let end = app.buttons["End"]
        XCTAssertTrue(end.exists)
        XCTAssertTrue(end.isHittable)
        try app.performAccessibilityAudit()
    }
}
