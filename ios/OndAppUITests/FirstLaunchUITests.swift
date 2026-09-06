import XCTest

@MainActor
final class FirstLaunchUITests: XCTestCase {
    func testOnboardingInheritsTheAppEnvironment() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-first-launch",
            "-profile.onboardingCompleted", "NO",
            "-plus.tier", "0",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Guided breathing, grounded in evidence."]
                .waitForExistence(timeout: 10)
        )

        XCTAssertTrue(app.otherElements["welcome-breath-guide"].exists)
        let welcome = XCTAttachment(screenshot: app.screenshot())
        welcome.name = "welcome-airflow"
        welcome.lifetime = .keepAlways
        add(welcome)

        let progress = app.descendants(matching: .any)["Setup progress"]
        XCTAssertTrue(progress.exists)
        XCTAssertEqual(progress.value as? String, "Step 1 of 5")
    }
}
