import Foundation
@testable import OndKit

/// A `HealthStore` whose every member already answers nothing, so a double
/// only writes down the part it is about — before this, three doubles each
/// spelled out every member. Every default is the "nothing to say"
/// answer rather than a plausible one: a double that forgets to override the
/// member under test should produce an obviously empty result.
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

    func writeMoodMayPrompt() async -> Bool {
        false
    }
}
