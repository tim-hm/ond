import Foundation
import OndKit

/// Starts a technique as this person has dialled it, or reports that a
/// subscription owns it.
///
/// Every route to a session that does not go through the exercise's own page
/// comes through here rather than calling `SessionModel.starting` itself. That
/// initialiser is failable for exactly one reason — the subscription gate — and
/// a second copy of the call is a second place for the gate to be forgotten.
/// Home's dial starts what the routing layer recommended and a reminder opens
/// whatever was scheduled, so neither passes the techniques list's lock, and
/// this is the only thing standing in for it.
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
    ///
    /// Plain and unprescribed, because this is the path a reminder and a deep
    /// link take: neither arrives through an occasion, so neither has a
    /// register to ask for nor a moment to stamp.
    func session(for technique: Technique) -> SessionModel? {
        session(
            for: technique,
            dialledWith: settings.overrides(for: technique),
            register: .plain,
            occasionSlug: nil
        )
    }

    /// The same start dialled by `overrides` instead of the saved dials — the
    /// coach's offer, applied for this session alone without touching what the
    /// person set themselves. Same gate, same failability, same reason.
    ///
    /// `register` and `occasionSlug` are undefaulted on this type's own
    /// argument: a second copy of the call is a second place for a gate to be
    /// forgotten, and what the record says about where a session came from is
    /// now one of the things this call decides. Every caller states its answer.
    func session(
        for technique: Technique,
        dialledWith overrides: TechniqueOverrides?,
        register: CopyRegister,
        occasionSlug: String?
    ) -> SessionModel? {
        let dialled = technique.dialled(with: overrides)
        return SessionModel.starting(
            dialled,
            for: tier,
            cues: SessionCues(
                mode: settings.cueMode,
                strength: settings.hapticStrength,
                sound: settings.sound
            ),
            recorder: sessions,
            register: register,
            occasionSlug: occasionSlug
        )
    }
}
