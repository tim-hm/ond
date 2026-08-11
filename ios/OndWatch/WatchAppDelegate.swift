import HealthKit
import os
import WatchKit

/// Answers the one thing the phone can do to this app while it is not running:
/// launch it.
///
/// `HKHealthStore.startWatchApp(with:)` wakes the watch app and hands its
/// delegate a workout configuration, with no payload and no mention of what it
/// is for — the session order itself travels separately, in the
/// `applicationContext` the phone wrote before making the call. What matters
/// here is speed rather than meaning: an app launched this way that does not
/// start a workout session promptly is suspended again, and the order that
/// arrives a beat later would land in a process no longer running to hear it.
///
/// So this takes the budget and stops. `startUnclaimed()` is what makes that
/// safe: the runtime hands itself back if no session claims it, so none of the
/// ordinary refusals — a technique this build lacks, an order the phone
/// withdrew, one the ledger has already spent — leaves a workout running for a
/// session that never happened. Everything about *which* session belongs to the
/// scene, which by then has a catalogue and an identity to decide it with.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private static let logger = Logger(category: "watch-link")

    func handle(_: HKWorkoutConfiguration) {
        Self.logger.notice("the phone launched this app into a workout session")
        WorkoutRuntime.shared.startUnclaimed()
    }
}
