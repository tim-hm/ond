import XCTest

@MainActor
final class PaywallLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testPurchaseControlsFollowTheBenefitsInTheBottomHalf() {
        openPaywall()

        let finalBenefit = app.staticTexts["Leaderboards, if you want them"]
        let monthly = app.buttons["paywall-plan-monthly"]
        let yearly = app.buttons["paywall-plan-yearly"]
        let purchase = app.buttons["paywall-purchase"]

        XCTAssertTrue(finalBenefit.exists)
        XCTAssertTrue(monthly.isHittable)
        XCTAssertTrue(yearly.isHittable)
        XCTAssertTrue(purchase.isHittable)
        XCTAssertGreaterThan(monthly.frame.minY, finalBenefit.frame.maxY)
        XCTAssertEqual(monthly.frame.minY, yearly.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(purchase.frame.minY, monthly.frame.maxY)
        XCTAssertGreaterThan(purchase.frame.midY, app.frame.midY)
        XCTAssertTrue(
            app.frame.contains(purchase.frame),
            "the purchase button must stand inside the screen, not below its edge"
        )
    }

    func testAccessibilityTextCanScrollThroughEveryPurchaseControl() {
        openPaywall(contentSize: "UICTContentSizeCategoryAccessibilityXL")

        for element in [
            app.buttons["paywall-plan-monthly"],
            app.buttons["paywall-plan-yearly"],
            app.buttons["paywall-purchase"],
            app.buttons["Restore Purchases"],
            app.descendants(matching: .any)["Privacy"],
            app.descendants(matching: .any)["Terms"],
        ] {
            reveal(element)
        }
    }

    private func openPaywall(contentSize: String? = nil) {
        app.launchArguments = ["--ui-testing", "--ui-testing-paywall", "-plus.tier", "0"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Everything that works offline stays free. Forever."]
                .waitForExistence(timeout: 10)
        )
    }

    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0 ..< 8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element) should be reachable by scrolling")
    }
}
