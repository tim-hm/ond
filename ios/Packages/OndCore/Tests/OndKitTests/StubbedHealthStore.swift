import Foundation
@testable import OndKit

/// A `HealthStore` whose every member already answers nothing, so a double only
/// writes down the part it is about.
///
/// Three doubles conform — one that records calls, one that scripts answers, one
/// that is deliberately silent — and before this each of them spelled out all
/// eight members. The tax was paid three times per member added, which is the
/// third-instance rule this codebase refactors on.
///
/// Every default is the "nothing to say" answer rather than a plausible one:
/// a double that forgets to override the member under test should produce an
/// obviously empty result, not a convincing reading.
protocol StubbedHealthStore: HealthStore {}

extension StubbedHealthStore {
    func requestReadAuthorization() async {}

    func requestMindfulWriteAuthorization() async {}

    func restingHeartRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func heartRateVariability(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func respiratoryRate(from _: Date, to _: Date) async -> [DailyQuantity] {
        []
    }

    func averageHeartRate(inEachOf _: [DateInterval]) async -> [WindowedQuantity] {
        []
    }

    func writeMindfulSession(from _: Date, to _: Date) async {}

    func writeMood(_: Mood, at _: Date) async {}
}
