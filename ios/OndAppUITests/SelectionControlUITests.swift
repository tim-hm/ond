import XCTest

@MainActor
final class SelectionControlUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testExerciseFiltersAreComfortableSelectionTargets() {
        app.tabBars.buttons["Exercises"].tap()

        let calm = app.buttons["Calm"]
        XCTAssertTrue(calm.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(calm.frame.height, 44)

        calm.tap()
        XCTAssertTrue(calm.isSelected)
        calm.tap()
        XCTAssertFalse(calm.isSelected)
    }

    func testMoodChoicesAreComfortableSelectionTargets() {
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
            let button = app.buttons[answer]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }
}
