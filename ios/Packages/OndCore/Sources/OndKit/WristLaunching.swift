import Foundation

/// Launches the paired watch's app into a workout session, or says it could
/// not.
///
/// A seam for the same reason `HealthStore` is one: what the phone decides
/// around the launch — `WristLaunchModel`'s states and its timeout — is the
/// logic worth testing, and none of it should need a paired watch to exercise.
/// The live implementation is `HealthKitHealthStore`, because the launch call
/// is `HKHealthStore` API and the sole-importer rule stays whole.
public protocol WristLaunching: Sendable {
    /// Asks the system to launch the watch app into a workout session.
    ///
    /// False covers every refusal alike — no paired watch, no watch app
    /// installed, the system declining — because the phone's response is the
    /// same fallback for all of them: say the wrist could not be reached and
    /// point at starting it there. True means only that the launch was
    /// dispatched; whether a session actually composes is the ack's news.
    func launchWatchApp() async -> Bool
}
