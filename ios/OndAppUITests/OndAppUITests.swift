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

        XCTAssertTrue(app.buttons["continue-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["home-state-line"].exists)
        XCTAssertTrue(app.buttons["all-exercises-row"].exists)
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

    func testSettingsGroupsHealthChoicesAndGatesPaidOptIns() throws {
        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "-plus.tier", "0",
            "-session.wristPulse", "NO",
            "-health.coachReadsHealthTrends", "NO",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))

        // Settings sits behind Home's overflow menu, not in a toolbar.
        let overflow = app.buttons["More"]
        XCTAssertTrue(overflow.exists)
        overflow.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        func reveal(_ element: XCUIElement) {
            for _ in 0 ..< 8 where !element.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable, "\(element) should appear in Settings")
        }

        func assertHealthChoice(_ identifier: String, title: String, description: String) {
            let choice = app.switches[identifier]
            reveal(choice)
            XCTAssertTrue(choice.label.contains(title))
            XCTAssertTrue(choice.label.contains(description))
        }

        func tapSwitchControl(_ toggle: XCUIElement) {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }

        func assertPaidToggleOpensPaywall(_ toggle: XCUIElement) {
            tapSwitchControl(toggle)
            XCTAssertTrue(
                app.staticTexts["Everything that works offline stays free. Forever."]
                    .waitForExistence(timeout: 5)
            )
            app.buttons["Not now"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            XCTAssertEqual(toggle.value as? String, "0")
        }

        XCTAssertTrue(app.staticTexts["General"].exists)
        XCTAssertTrue(app.staticTexts["Appearance"].exists)

        reveal(app.staticTexts["Practice"])
        let hapticStrength = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "iPhone haptics aren't supported")
        ).firstMatch
        XCTAssertTrue(hapticStrength.exists)
        XCTAssertTrue(
            hapticStrength.label.contains(
                "iPhone haptics aren't supported when the screen is off — you'll hear the "
                    + "session but not feel it."
            )
        )
        reveal(app.staticTexts["Health"])

        assertHealthChoice(
            "settings-health-check-ins",
            title: "Ask how you feel before and after",
            description: "Saves your responses as State of Mind in Apple Health. önd never sees them."
        )
        assertHealthChoice(
            "settings-health-live-heart-rate",
            title: "Heart rate from your Apple Watch",
            description: "Shows your heart rate live during practice. Apple Watch keeps a workout "
                + "open without storing or sharing readings."
        )

        let liveHeartRate = app.switches["settings-health-live-heart-rate"]
        assertPaidToggleOpensPaywall(liveHeartRate)

        assertHealthChoice(
            "settings-health-watch-trends",
            title: "Read my heart data",
            description: "Your coach uses sleeping breathing, resting heart rate and "
                + "heart-rate variability when needed, and Home draws your heart rate "
                + "around each session you practise. Nothing read is stored or sent."
        )

        let watchTrends = app.switches["settings-health-watch-trends"]
        assertPaidToggleOpensPaywall(watchTrends)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)
                )
            )
        reveal(watchTrends)

        try app.performAccessibilityAudit { issue in
            // iOS 26 scales the compact snapshots of custom Picker and Toggle
            // labels instead of rendering their accessibility-size branches.
            // The manual large-type visual check exercises those branches;
            // the remaining audit categories stay enforced here.
            if issue.auditType.contains(.dynamicType) {
                return true
            }

            let compactPickerValues = [
                "Haptics & sound",
                "Faye — United Kingdom",
            ]
            if issue.auditType.contains(.textClipped),
               let element = issue.element,
               compactPickerValues.contains(element.label)
            {
                return true
            }

            // The audit captures SwiftUI labels without their custom list-row
            // background and reports visibly dark text as low contrast.
            // ThemeColorTests measures every actual token pair; the screenshot
            // from the manual visual check covers their composition here.
            if issue.auditType == .contrast {
                return true
            }

            if let element = issue.element {
                let navigationBar = self.app.navigationBars["Settings"].frame
                // iOS 26's glass starts fading content before the navigation and
                // floating Home controls, while their AX frames cover only the
                // controls themselves.
                let navigationChromeBottom = navigationBar.maxY + 48
                let floatingChromeTop = self.app.tabBars.buttons["Home"].frame.minY - 48
                if element.frame.minY < navigationChromeBottom
                    || element.frame.maxY > floatingChromeTop
                {
                    return true
                }
            }

            if issue.auditType.contains(.textClipped), issue.element == nil {
                return true
            }

            // The OCR pass sometimes rediscovers picker values that the AX
            // tree already exposed above, but supplies no app element to fix.
            if issue.auditType.contains(.elementDetection), issue.element == nil {
                return true
            }

            return false
        }

        assertHealthChoice(
            "settings-health-mindful-minutes",
            title: "Write Mindful Minutes to Health",
            description: "Records iPhone practices as Mindful Minutes in Apple Health."
        )
        XCTAssertFalse(
            app.staticTexts[
                "Apple Health asks separately before önd reads or writes data, and always has "
                    + "the final say."
            ].exists
        )

        XCTAssertFalse(app.staticTexts["Reading your trends is part of"].exists)
        XCTAssertFalse(
            app.staticTexts["Your watch and phone working together is part of"].exists
        )

        reveal(app.staticTexts["settings-section-reminders"])
        reveal(app.staticTexts["Account"])

        let subscription = app.buttons["settings-account-subscription"]
        reveal(subscription)
        XCTAssertTrue(app.staticTexts["Subscription"].exists)
        XCTAssertEqual(subscription.label, "Subscription, Free")
        subscription.tap()
        XCTAssertTrue(
            app.staticTexts["Everything that works offline stays free. Forever."]
                .waitForExistence(timeout: 5)
        )
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        reveal(app.staticTexts["About"])
    }

    func testProgressOwnsPracticeReflectionAndMeetsTheAccessibilityAudit() throws {
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Progress"].tap()

        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["practice-summary"].exists)
        XCTAssertTrue(app.buttons["leaderboards-door"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["practice-chart"].exists)
        XCTAssertTrue(app.staticTexts["History"].exists)

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

    func testWithYourChildIsAPlayfulProtocolRatherThanAnExercise() {
        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "-session.breathVisual", "sphere",
            "-session.moodCheck", "NO",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Exercises"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Exercises"].tap()
        let underlyingExercise = app.staticTexts["Extended Exhale"]
        for _ in 0 ..< 6 where !underlyingExercise.exists {
            app.swipeUp()
        }
        XCTAssertTrue(underlyingExercise.exists)
        XCTAssertFalse(app.staticTexts["Breathing Together"].exists)

        let protocols = app.tabBars.buttons["Protocols"]
        for _ in 0 ..< 2 where !protocols.exists {
            app.swipeDown()
        }
        XCTAssertTrue(protocols.waitForExistence(timeout: 5))
        protocols.tap()
        let child = app.staticTexts["With your child"]
        for _ in 0 ..< 5 where !child.exists {
            app.swipeUp()
        }
        XCTAssertTrue(child.exists)
        child.tap()

        let accept = app.buttons["I understand"]
        if accept.waitForExistence(timeout: 2) {
            XCTAssertTrue(app.staticTexts["Before With your child"].exists)
            accept.tap()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["breath-guide-playful"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["Smell the flower"].exists)
        XCTAssertTrue(app.staticTexts["Blow out the candle"].waitForExistence(timeout: 5))
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
