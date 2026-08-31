import Foundation

/// Launches the paired watch's app into a workout session, or says it could
/// not. A seam so `WristLaunchModel`'s states and timeout can be tested
/// without a paired watch. The live `WristLauncher` holds `HKHealthStore`
/// for the launch call and never reads a sample.
public protocol WristLaunching: Sendable {
    /// Asks for whatever a launch will need, without launching anything. The
    /// launch needs this app's workout share grant, and requesting it shows a
    /// system sheet the first time — which once landed over a running
    /// countdown, so the asking happens at the switch that turns the feature
    /// on. Answers nothing: a refusal is indistinguishable from a grant here.
    func prepare() async

    /// Asks the system to launch the watch app into a workout session. False
    /// covers every refusal alike — no paired watch, no app, the system
    /// declining — because the phone answers all with one fallback. True
    /// means only that the launch was dispatched; whether a session composes
    /// is the ack's news.
    func launchWatchApp() async -> Bool
}
