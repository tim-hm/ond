import OndKit
import OndUI
import SwiftUI

/// The wearer's heart rate, while a paired watch is sending one. Nothing here
/// interprets it — no target, no zone, no threshold colour — and it says
/// nothing when there is none: absence is this feature's whole failure mode.
/// It owns the environment read so an arriving rate redraws only this capsule,
/// not the breath guide. `PulseCapsule` takes the rate so a simulator can draw it.
struct PulseBadge: View {
    @Environment(PulseMonitor.self) private var pulse

    var body: some View {
        PulseCapsule(beatsPerMinute: pulse.beatsPerMinute)
    }
}

/// One rate, drawn — or the space one would take, when there is none. It
/// keeps its place in the layout either way: a rate arrives seconds into a
/// session and stops when a wrist comes off, and a badge that took its space
/// only while speaking would move the breath guide above it twice a session.
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
                // One bounce per arriving reading, not per heartbeat: the
                // wrist sends an average every `PulseRelay.spacing`, so the
                // number knows nothing about when a beat landed. Reduce Motion
                // nils the value rather than dropping the modifier, so the
                // icon keeps one identity across the setting.
                .symbolEffect(.bounce, value: reduceMotion ? nil : beatsPerMinute)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.Ink.primary)
        // Twice the inset across as down, because the shape below is a capsule:
        // its ends curve away from the content, so equal padding leaves the
        // heart in the arc rather than inside it.
        .padding(.horizontal, Theme.Spacing.standard)
        .padding(.vertical, Theme.Spacing.close)
        // The transport controls' material: legible over whichever accent the
        // technique brought. Conditional because a material composites a blur
        // and the silent badge is the common case — most sessions have no
        // wrist. The `Label` stays unconditional: it reserves the height, and
        // a branch there would give the symbol effect a new identity.
        .background {
            if beatsPerMinute != nil {
                Capsule().fill(.thinMaterial)
            }
        }
        .opacity(beatsPerMinute == nil ? 0 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(beatsPerMinute.map { "\($0) beats per minute" } ?? "")
        // Invisible is not enough for VoiceOver: the placeholder is still a
        // number, and read aloud it would be a heart rate nobody measured.
        .accessibilityHidden(beatsPerMinute == nil)
    }
}

// The same settling heart a rehearsing simulator draws, on the ground the
// badge sits on — `PulseMonitor.rehearsedRate(after:)` rather than a second
// curve. Every two seconds rather than the wrist's eight: this is for
// looking at the bounce, not judging the cadence.
#Preview("Wrist pulse") {
    TimelineView(.periodic(from: .now, by: 2)) { context in
        let arrivals = Int(context.date.timeIntervalSinceReferenceDate) / 2
        PulseCapsule(beatsPerMinute: PulseMonitor.rehearsedRate(after: arrivals))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accentGround(Theme.Accent.settle)
}
