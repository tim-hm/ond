import Foundation
@testable import OndKit
import os
import Testing

@Suite("HealthKit read boundary")
struct HealthKitReadBoundaryTests {
    private enum TestError: LocalizedError {
        case denied
        case queryFailed

        var errorDescription: String? {
            switch self {
            case .denied: "authorization denied"
            case .queryFailed: "query failed"
            }
        }
    }

    @Test("Denied authorization returns no value and names each sample type")
    func deniedAuthorizationIsDiagnosed() async {
        let failures = OSAllocatedUnfairLock(initialState: [HealthKitReadFailure]())
        let boundary = HealthKitReadBoundary { failure in
            failures.withLock { $0.append(failure) }
        }

        let result: Void? = await boundary.perform(
            .authorization,
            sampleTypes: ["resting-heart-rate", "heart-rate-variability"]
        ) {
            throw TestError.denied
        }

        #expect(result == nil)
        #expect(failures.withLock { $0 } == [
            HealthKitReadFailure(
                operation: .authorization,
                sampleType: "resting-heart-rate",
                reason: "authorization denied"
            ),
            HealthKitReadFailure(
                operation: .authorization,
                sampleType: "heart-rate-variability",
                reason: "authorization denied"
            ),
        ])
    }

    @Test("A query failure returns no data and identifies its sample type")
    func queryFailureIsDiagnosed() async {
        let failures = OSAllocatedUnfairLock(initialState: [HealthKitReadFailure]())
        let boundary = HealthKitReadBoundary { failure in
            failures.withLock { $0.append(failure) }
        }

        let result: [Int]? = await boundary.perform(
            .query,
            sampleTypes: ["respiratory-rate"]
        ) {
            throw TestError.queryFailed
        }

        #expect(result == nil)
        #expect(failures.withLock { $0 } == [
            HealthKitReadFailure(
                operation: .query,
                sampleType: "respiratory-rate",
                reason: "query failed"
            ),
        ])
    }

    @Test("An empty successful query stays empty without a failure record")
    func emptyQueryIsNotAFailure() async {
        let failures = OSAllocatedUnfairLock(initialState: [HealthKitReadFailure]())
        let boundary = HealthKitReadBoundary { failure in
            failures.withLock { $0.append(failure) }
        }

        let result: [Int]? = await boundary.perform(.query, sampleTypes: ["resting-heart-rate"]) {
            []
        }

        #expect(result == [])
        #expect(failures.withLock { $0 }.isEmpty)
    }
}
