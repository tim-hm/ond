import Foundation
@testable import OndKit

/// Answers from a script and remembers every call, so a test can prove
/// Health was never touched — not merely that nothing came back.
actor ScriptedHealthStore: StubbedHealthStore {
    private(set) var readAuthorizationRequests = 0
    private(set) var queries = 0
    private let restingHeartRate: [DailyQuantity]
    private let heartRateVariability: [DailyQuantity]
    private let respiratoryRate: [DailyQuantity]
    private let heartRates: [WindowedQuantity]

    init(
        restingHeartRate: [DailyQuantity] = [],
        heartRateVariability: [DailyQuantity] = [],
        respiratoryRate: [DailyQuantity] = [],
        heartRates: [WindowedQuantity] = []
    ) {
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.respiratoryRate = respiratoryRate
        self.heartRates = heartRates
    }

    func requestReadAuthorization() async {
        readAuthorizationRequests += 1
    }

    func restingHeartRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        queries += 1
        return restingHeartRate
    }

    func heartRateVariability(from _: Date, to _: Date) async -> [DailyQuantity] {
        queries += 1
        return heartRateVariability
    }

    func respiratoryRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        queries += 1
        return respiratoryRate
    }

    /// Answers only for the windows it was actually asked about, so a test
    /// cannot pass on a reading the caller never requested.
    func averageHeartRate(inEachOf windows: [DateInterval]) async -> [WindowedQuantity] {
        queries += 1
        return heartRates.filter { windows.contains($0.window) }
    }
}
