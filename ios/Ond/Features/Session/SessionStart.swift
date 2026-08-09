import Foundation
import OndKit

/// Starts a technique as this person has dialled it, or reports that a
/// subscription owns it.
///
/// Every route to a session that does not go through the exercise's own page
/// comes through here rather than calling `SessionModel.starting` itself. That
/// initialiser is failable for exactly one reason — the subscription gate — and
/// a second copy of the call is a second place for the gate to be forgotten.
/// Home's wheel suggests from the whole catalogue and a reminder opens whatever
/// was scheduled, so neither passes the techniques list's lock, and this is the
/// only thing standing in for it.
///
/// It resolves the technique the same way the detail screen's Begin does, so no
/// two ways in can start different sessions.
@MainActor
struct SessionStart {
    let sessions: any SessionRecording
    let settings: SessionSettings
    let tier: SubscriptionTier

    /// The session to present, or nil where `technique` is locked and the
    /// paywall is what should open instead.
    func session(for technique: Technique) -> SessionModel? {
        session(for: technique, dialledWith: settings.overrides(for: technique))
    }

    /// The same start dialled by `overrides` instead of the saved dials — the
    /// coach's offer, applied for this session alone without touching what the
    /// person set themselves. Same gate, same failability, same reason.
    func session(
        for technique: Technique,
        dialledWith overrides: TechniqueOverrides?
    ) -> SessionModel? {
        let dialled = technique.dialled(with: overrides)
        return SessionModel.starting(
            dialled,
            for: tier,
            cues: SessionCues(mode: settings.cueMode, strength: settings.hapticStrength),
            recorder: sessions
        )
    }
}
