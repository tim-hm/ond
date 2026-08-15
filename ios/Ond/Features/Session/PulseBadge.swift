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
/// The read is all this half does. The drawing is `PulseCapsule` below, which
/// takes the rate rather than reaching for it — a wrist and a sensor are two
/// pieces of hardware a simulator does not have, so a badge that only ever
/// sourced its own number could not be looked at anywhere but on a real phone
/// with a real watch on a real arm.
struct PulseBadge: View {
    @Environment(PulseMonitor.self) private var pulse

    var body: some View {
        PulseCapsule(beatsPerMinute: pulse.beatsPerMinute)
    }
}

/// One rate, drawn — or the space one would take, when there is none.
///
/// Silent is not the same as absent, and this keeps its place in the layout
/// either way. A rate arrives a few seconds into a session and stops arriving
/// the moment a wrist comes off, so a badge that took its space only while it
/// had something to say would move the breath guide above it twice a session. A
/// screen read through half-closed eyes cannot also be moving.
private struct PulseCapsule: View {
    let beatsPerMinute: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            // The placeholder is never drawn; it is what gives a silent badge the
            // height of a speaking one, at every text size, without a constant
            // here having to stay in agreement with the type ramp.
            Text(beatsPerMinute.map(String.init) ?? "00")
                .monospacedDigit()
        } icon: {
            Image(systemName: "heart.fill")
                // One beat per arriving reading, not per heartbeat. A heart at 60
                // is a second-long rhythm and the breath guide beside it is a
                // ten-second one; two periods on one screen is the opposite of
                // what this screen is for. It also cannot honestly be done: the
                // wrist sends every `PulseRelay.spacing`, so the number is an
                // average up to that old and knows nothing about when a beat
                // actually landed. Moving when the figure changes claims only
                // what the figure claims.
                //
                // Reduce Motion nils the value rather than dropping the modifier,
                // so the icon keeps one identity across the setting instead of
                // being torn down and rebuilt mid-session.
                .symbolEffect(.bounce, value: reduceMotion ? nil : beatsPerMinute)
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

// A settling heart on the ground the badge actually sits on.
//
// Every two seconds rather than the wrist's eight, because this is for looking
// at the bounce and not for judging the cadence — on hardware three quarters of
// these arrivals would be the same number re-sent, and the badge would hold
// still through them.
#Preview("Wrist pulse") {
    TimelineView(.periodic(from: .now, by: 2)) { context in
        let arrivals = Int(context.date.timeIntervalSinceReferenceDate) / 2
        PulseCapsule(beatsPerMinute: 74 - arrivals % 16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accentGround(Theme.Accent.settle)
}
