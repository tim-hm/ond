import SwiftUI

public extension View {
    /// The session flow's one primary control: a full-width capsule washed with
    /// the accent, strong enough to read as the way forward without shouting
    /// over the screen it concludes.
    ///
    /// One modifier rather than an inline recipe because the same control ends
    /// three screens — the invitation's Begin, the summary's Done, a warning's
    /// I understand — and a retune of its opacity, padding or shape has to land
    /// on all of them at once or the flow's one button quietly forks.
    ///
    /// One of the app's three primary-button voices, and the rule for choosing
    /// is the ground, not the feature: **this capsule** on the session cover's
    /// accent wash, where a filled system button would shout over a screen
    /// built to be quiet; **`.glassProminent`** where the surface itself is
    /// glass or a gradient — onboarding, the consent screen, the composer bar;
    /// **`.borderedProminent` + `.controlSize(.large)`** everywhere the ground
    /// is the plain palette — Coach's invitations, the paywall, the check-in
    /// tests. A fourth voice is a fork, not a variation; before adding one,
    /// pick the family whose ground this is.
    func capsuleAction(_ accent: Color) -> some View {
        font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.close)
            .background(accent.opacity(0.2), in: Capsule())
    }
}
