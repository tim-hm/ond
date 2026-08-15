import Foundation
@testable import OndKit
import StoreKit
import Testing

private enum ProductLookupFailure: Error, Equatable {
    case offline
}

@Suite("StoreKit boundary")
struct StoreKitStoreFrontTests {
    /// Every known product is a subscription. A verified value that lacks an
    /// expiry must disappear at the StoreKit boundary instead of becoming a
    /// permanent entitlement.
    @Test("A transaction without an expiry is rejected")
    func missingExpiryIsRejected() {
        let transaction = StoreKitStoreFront.subscriptionTransaction(.init(
            id: 1,
            productID: SubscriptionPlan.monthly.productIdentifier,
            expirationDate: nil,
            revocationDate: nil,
            jws: "jws",
            isLocallySigned: false
        ))

        #expect(transaction == nil)
    }

    /// A network or App Store failure is not proof that the product does not
    /// exist. The purchase layer needs the original distinction so it does not
    /// turn a retryable outage into the paywall's permanent unavailable state.
    @Test("A failed product lookup remains its original purchase error")
    func failedLookupPropagatesFromPurchase() async {
        let front = StoreKitStoreFront(productLookup: { _ in
            throw ProductLookupFailure.offline
        })

        await #expect(throws: ProductLookupFailure.offline) {
            try await front.purchase(.monthly)
        }
        #expect(await front.products().isEmpty)
    }

    /// Only an App Store response that successfully contains none of the
    /// requested products means this build has nothing to sell.
    @Test("A successful empty lookup is product unavailable")
    func emptyLookupIsUnavailable() async {
        let front = StoreKitStoreFront(productLookup: { _ in [] })

        await #expect(throws: StoreFrontError.productUnavailable) {
            try await front.purchase(.monthly)
        }
    }

    /// StoreKit can add a period unit without making this build understand what
    /// its value means. No trial is safer than advertising that raw value as a
    /// number of days.
    @Test(
        "Supported period units convert to days",
        arguments: [
            (StoreKitStoreFront.PeriodUnit.day, 1),
            (.week, 7),
            (.month, 30),
            (.year, 365),
        ]
    )
    func supportedPeriodUnits(unit: StoreKitStoreFront.PeriodUnit, days: Int) {
        #expect(
            StoreKitStoreFront.introductoryOffer(
                periodValue: 1,
                periodCount: 1,
                unit: unit,
                isEligible: true
            )?.trialDays == days
        )
    }

    @Test("An unknown period unit produces no trial offer")
    func unknownPeriodUnitOmitsTheOffer() {
        #expect(
            StoreKitStoreFront.introductoryOffer(
                periodValue: 1,
                periodCount: 1,
                unit: .unsupported,
                isEligible: true
            ) == nil
        )
    }
}
