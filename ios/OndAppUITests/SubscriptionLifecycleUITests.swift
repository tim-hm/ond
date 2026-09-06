import StoreKit
import StoreKitTest
import XCTest

@MainActor
final class SubscriptionLifecycleUITests: XCTestCase {
    func testRestorePurchaseAndExpiry() async throws {
        continueAfterFailure = false
        let session = try SKTestSession(configurationFileNamed: "Ond")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        do {
            _ = try await session.buyProduct(identifier: "xyz.holmie.ond.plus.monthly2")
        } catch StoreKitError.notEntitled {
            throw XCTSkip(
                "StoreKit's test service refused configuration. Purchase verification remains blocked."
            )
        }
        session.clearTransactions()

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-paywall", "-plus.tier", "0"]
        app.launch()
        let purchase = app.buttons["paywall-purchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 10))
        app.buttons["Restore Purchases"].tap()
        XCTAssertTrue(app.staticTexts["No active subscription was found for this Apple account."]
            .waitForExistence(timeout: 30))

        app.buttons["paywall-plan-monthly"].tap()
        purchase.tap()
        XCTAssertTrue(purchase.waitForNonExistence(timeout: 30))
        XCTAssertFalse(session.allTransactions().isEmpty)

        app.buttons["Settings"].tap()
        let subscription = app.buttons["settings-account-subscription"]
        for _ in 0 ..< 8 where !subscription.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(subscription.label, "önd+")

        try session.expireSubscription(productIdentifier: "xyz.holmie.ond.plus.monthly2")
        let expired = expectation(
            for: NSPredicate(format: "label == %@", "Free"),
            evaluatedWith: subscription
        )
        await fulfillment(of: [expired], timeout: 15)
    }
}
