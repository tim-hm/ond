import OndUI
import SwiftUI

/// The wearer's heart rate, while a paired watch is sending one.
///
/// A badge and not a panel: this is the one number a session shows that the
/// session is not asking for, and reading it should cost a glance. Nothing here
/// interprets it — no target, no zone, no colour that changes at a threshold. A
/// breathing practice slows a heart on its own, and a screen that graded the
/// number would turn a settling exercise into a performance.
///
/// It has no absent state, by design. The screen draws one of these or nothing at
/// all, because every reason there is no rate — no watch, no grant, a wrist out of
/// range, a workout already running on it — is a reason a person would rather see
/// their session than an explanation.
struct PulseBadge: View {
    let beatsPerMinute: Int

    var body: some View {
        Label {
            Text("\(beatsPerMinute)")
                .monospacedDigit()
        } icon: {
            Image(systemName: "heart.fill")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.Ink.primary)
        .padding(.horizontal, Theme.Spacing.tight)
        .padding(.vertical, Theme.Spacing.close)
        // The material the transport controls wear, for the same reason: it is
        // legible over whichever accent the technique brought without the badge
        // having to know what that accent is.
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heart rate")
        .accessibilityValue("\(beatsPerMinute) beats per minute")
    }
}
