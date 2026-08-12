import Foundation

/// Launches the paired watch's app into a workout session, or says it could
/// not.
///
/// A seam for the same reason `HealthStore` is one: what the phone decides
/// around the launch — `WristLaunchModel`'s states and its timeout — is the
/// logic worth testing, and none of it should need a paired watch to exercise.
/// The live implementation is `WristLauncher`, which holds `HKHealthStore` for
/// the launch call and never reads a sample — the line `HealthKitHealthStore`'s
/// own doc draws.
public protocol WristLaunching: Sendable {
    /// Asks for whatever a launch will need, without launching anything.
    ///
    /// Exists so the asking happens where a person expects to be asked. The
    /// launch needs this app's own workout share grant, and requesting it shows a
    /// system sheet the first time — which, on the path where a session quietly
    /// looks for a heart rate, landed over a countdown that carried on behind it.
    /// Called from the switch that turns the feature on instead.
    ///
    /// Answers nothing: a refusal is indistinguishable from a grant here, and the
    /// only consequence either way is whether a later launch succeeds.
    func prepare() async

    /// Asks the system to launch the watch app into a workout session.
    ///
    /// False covers every refusal alike — no paired watch, no watch app
    /// installed, the system declining — because the phone's response is the
    /// same fallback for all of them: say the wrist could not be reached and
    /// point at starting it there. True means only that the launch was
    /// dispatched; whether a session actually composes is the ack's news.
    func launchWatchApp() async -> Bool
}
