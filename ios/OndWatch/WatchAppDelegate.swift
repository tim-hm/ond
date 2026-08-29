import HealthKit
import os
import WatchKit

/// Answers the one thing the phone can do to this app while it is not
/// running: launch it. `startWatchApp` hands over a workout configuration
/// with no payload — the order travels separately in `applicationContext`,
/// and an app that starts no workout promptly is suspended before it lands.
/// So this takes the budget and stops; `startUnclaimed()` hands it back if nothing claims it.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private static let logger = Logger(category: "watch-link")

    func handle(_: HKWorkoutConfiguration) {
        Self.logger.notice("the phone launched this app into a workout session")
        WorkoutRuntime.shared.startUnclaimed()
    }
}
