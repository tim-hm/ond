import Foundation
import OndKit
import os
import WatchKit

/// The runtime budget a guided breath needs. Without it the app stops
/// getting time the moment the wrist drops and the taps silently stop.
/// `WKBackgroundModes: mindfulness` in the target's Info.plist is what makes
/// `start()` succeed at all. Expiry, refusal and a never-started session land
/// the same — budget gone, logged, breathing on — so no ending, no view state.
@MainActor
final class ExtendedRuntime: NSObject {
    /// `nonisolated` because the delegate callbacks below log where they land,
    /// and a `static let` on a main-actor type is main-actor-isolated by default.
    private nonisolated static let logger = Logger(category: "session-runtime")

    private var session: WKExtendedRuntimeSession?

    /// Asks for the budget. A second call while one is running is a no-op — the
    /// system refuses overlapping sessions, and asking anyway would invalidate
    /// the one already granted.
    func start() {
        guard session == nil else { return }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        session.start()
    }

    /// Hands the budget back. Called as the player goes away, so a finished
    /// session does not keep the wrist awake while somebody reads a summary.
    func invalidate() {
        session?.invalidate()
        session = nil
    }
}

/// WatchKit calls these on the main thread, but the protocol carries no
/// isolation, so the one that touches state hops explicitly. The session itself
/// is never captured across the hop — it is not `Sendable`, and there is nothing
/// on it these need.
extension ExtendedRuntime: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_: WKExtendedRuntimeSession) {
        Self.logger.notice("the extended runtime session started")
    }

    /// The last warning before the budget runs out. Nothing to do but say so:
    /// stopping the session here would end somebody's breathing because the
    /// operating system got bored.
    nonisolated func extendedRuntimeSessionWillExpire(_: WKExtendedRuntimeSession) {
        Self.logger.notice("the extended runtime session is about to expire")
    }

    nonisolated func extendedRuntimeSession(
        _: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: (any Error)?
    ) {
        // Covers a session that never started as well as one that ran out —
        // both leave the app without a budget, and the difference matters only
        // in the log.
        if let error {
            Self.logger.notice(
                "the extended runtime session ended: reason \(reason.rawValue), \(error.localizedDescription, privacy: .public)"
            )
        } else {
            Self.logger.notice("the extended runtime session ended: reason \(reason.rawValue)")
        }
        Task { @MainActor in self.session = nil }
    }
}
