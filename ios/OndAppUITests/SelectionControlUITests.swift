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

        XCTAssertTrue(app.buttons["Okay"].waitForExistence(timeout: 2))
        for answer in ["Bad", "Not good", "Okay", "Good", "Great"] {
            let button = app.buttons[answer]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }
}
