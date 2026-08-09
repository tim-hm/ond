import OndKit

/// What the app puts in front of everything else on a launch, before anything
/// can be breathed.
///
/// Two states rather than two booleans, because they must never both be true:
/// onboarding already carries the safety terms as its last step, so the standalone
/// version is only ever for an install that finished the flow before that step
/// existed.
enum FirstRunGate: Identifiable {
    /// The whole first-run flow, for an install that has answered nothing.
    case onboarding
    /// The safety terms alone, for somebody who onboarded before they existed —
    /// no record means never asked, and never asked means ask.
    case safety

    var id: Self {
        self
    }

    /// What `profiles` and `consent` between them say is still outstanding.
    @MainActor
    static func pending(profiles: ProfileStore, consent: SafetyConsentStore) -> Self? {
        guard profiles.hasCompletedOnboarding else { return .onboarding }
        return consent.needsConsent ? .safety : nil
    }
}
