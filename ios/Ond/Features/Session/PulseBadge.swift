import OndKit
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
/// It reads the rate itself rather than taking one, and says nothing when there
/// is none. Both halves are deliberate. The absence is this feature's whole
/// failure mode — no watch, no grant, a wrist out of range, a workout already
/// running on it — and a person would rather see their session than an
/// explanation. And owning the read is what confines a reading's redraw to this
/// capsule: read one level up, in the player's own body, every arriving rate
/// invalidated the breath guide and both of its timelines.
///
/// Silent is not the same as absent, though, and this one keeps its place in the
/// layout either way. A rate arrives a few seconds into a session and stops
/// arriving the moment a wrist comes off, so a badge that took its space only
/// while it had something to say would move the breath guide above it twice a
/// session. A screen read through half-closed eyes cannot also be moving.
struct PulseBadge: View {
    @Environment(PulseMonitor.self) private var pulse

    var body: some View {
        let beatsPerMinute = pulse.beatsPerMinute

        Label {
            // The placeholder is never drawn; it is what gives a silent badge the
            // height of a speaking one, at every text size, without a constant
            // here having to stay in agreement with the type ramp.
            Text(beatsPerMinute.map(String.init) ?? "00")
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
        .opacity(beatsPerMinute == nil ? 0 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heart rate")
        .accessibilityValue("\(beatsPerMinute ?? 0) beats per minute")
        // Invisible is not enough for VoiceOver: the placeholder is still a
        // number, and read aloud it would be a heart rate nobody measured.
        .accessibilityHidden(beatsPerMinute == nil)
    }
}
