import OndKit
import OndStyle
import OndUI
import SwiftUI
import WidgetKit

/// The session as it appears on the lock screen and as a banner on an older
/// phone: one glance card for the phase, progress, practice and remaining time,
/// over the session's own night-water ground.
///
/// Two elements move between snapshots with no update from the app — the phase
/// track and the whole-session timer, both handed to the system as absolute
/// dates. Everything else is a still frame per push.
///
/// The transport pair sits under them rather than only on the expanded Island:
/// reaching a session means picking the phone up, and a card that shows a
/// running session without offering the way out of it makes somebody unlock to
/// do the one thing they reached for. The buttons run `LiveActivityIntent`s in
/// the app's process, so they work from here without unlocking anything.
struct SessionLockScreenView: View {
    let attributes: SessionActivityAttributes
    let presence: SessionPresence

    /// The card's radius. The system publishes no radius for its lock-screen
    /// container, so this is the spec's own number rather than a match to
    /// anything measurable.
    private static let cardRadius: CGFloat = 34

    /// The card's ground — deep teal light falling away to near-black, fixed
    /// in both appearances like the in-app session's `deepGround`, and a local
    /// constant for its reason: the spec defines no light variant, and a
    /// catalogue token would oblige the integrity tests to invent one.
    private static let ground = RadialGradient(
        colors: [
            Color(red: 0x1B / 255, green: 0x33 / 255, blue: 0x3C / 255),
            Self.groundEdge,
        ],
        center: .topLeading,
        startRadius: 0,
        endRadius: 360
    )

    /// Where the ground's light has fully fallen away. Doubles as the system
    /// container's tint below: hosts that platter the activity at their own
    /// radius — the banner, StandBy, the watch's mirror — then frame the card
    /// in its own darkness, where a cleared container would show wallpaper
    /// through every corner the r34 card does not reach.
    private static let groundEdge = Color(red: 0x0A / 255, green: 0x10 / 255, blue: 0x13 / 255)

    /// The same colour the app is showing this second. The register rides on the
    /// per-beat state rather than the attributes, so it is read from `presence`
    /// and the goal from `attributes` — the one place those two halves meet.
    private var accent: Color {
        presence.register.accent(over: attributes.goal)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.close) {
            statusRow
            SessionControls(attributes: attributes, presence: presence)
        }
        // Close on both insets, not standard: the lock screen clips a
        // presentation past roughly 160 points, and with the transport row this
        // card measures over that at standard. Of everything on it the two
        // insets are the height that costs least to give up — the tap targets
        // are not negotiable, and the glyph cannot drop below 44 without losing
        // its lit core.
        .padding(Theme.Spacing.close)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .padding(Theme.Spacing.close)
        .background(Self.ground, in: RoundedRectangle(cornerRadius: Self.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cardRadius)
                .strokeBorder(Theme.Surface.line, lineWidth: 0.5)
        }
        // The card draws its own ground, so the system's default material
        // behind it would double the chrome — tinted to the ground's edge,
        // beside the ground that decides it.
        .activityBackgroundTint(Self.groundEdge)
        // The ground above is fixed and dark, but the label's system inks and
        // inner material still adapt to the lock screen's appearance — in the
        // light appearance that is near-black words on near-black water. Forcing
        // the subtree dark keeps them on the variants this ground was built
        // against; the in-app player carries the same line.
        .environment(\.colorScheme, .dark)
    }

    private var statusRow: some View {
        HStack(spacing: Theme.Spacing.standard) {
            BreathGlyph(
                // 44, not smaller: the glance core is 0.293 of the side, and
                // below `BreathGlyph`'s 12-point flat-fill threshold it loses
                // the lit-vapour treatment this surface is meant to keep.
                side: 44,
                pose: .pushed(for: presence),
                layers: .glance
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
                    // Scaled rather than truncated: the playful register
                    // writes "Blow out the candle" where a plain phase writes
                    // "Hold", and at 26 points that is wider than the row.
                    Text(presence.instruction)
                        .displaySerif(size: 26)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Spacer(minLength: Theme.Spacing.close)

                    // The digits win the row. Without this the two texts
                    // carry equal weight and the long instruction above takes
                    // the space out of the number instead of out of itself.
                    remainingTime
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                PhaseTrack(presence: presence, accent: accent)

                Text(presence.caption(of: attributes.techniqueName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// A person-ended retention counts up; a finite session counts down. They
    /// are mutually exclusive because any plan with an open-ended hold has no
    /// honest wall-clock end to print.
    @ViewBuilder
    private var remainingTime: some View {
        if let heldSince = presence.heldSince {
            Text(heldSince, style: .timer)
                .font(.headline)
                .monospacedDigit()
        } else {
            SessionRemainingTime(presence: presence)
                .font(.headline)
        }
    }
}
