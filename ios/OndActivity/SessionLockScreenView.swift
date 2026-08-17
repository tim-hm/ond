import OndKit
import OndStyle
import OndUI
import SwiftUI
import WidgetKit

/// The session as it appears on the lock screen and as a banner on an older
/// phone: the breath, what it is, and the controls, over the session's own
/// night-water ground.
///
/// One row and one line, because a lock screen glanced at mid-breath has room
/// for no more. Everything that would make it taller — the round, the cycle,
/// how far through the session is — is in the app, where somebody is looking
/// rather than glancing. The phase's own motion lives in the track under the
/// row: the glyph is pushed one step per update and cannot animate, so the
/// track is the one element the system sweeps between pushes.
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
        VStack(spacing: Theme.Spacing.standard) {
            HStack(spacing: Theme.Spacing.standard) {
                BreathGlyph(
                    side: 44,
                    pose: .pushed(for: presence),
                    layers: .glance
                )
                SessionCueLabel(attributes: attributes, presence: presence)
                Spacer(minLength: Theme.Spacing.close)
                SessionControls(
                    attributes: attributes,
                    presence: presence,
                    accent: accent
                )
            }
            PhaseTrack(presence: presence, accent: accent)
        }
        .padding(Theme.Spacing.standard)
        .background(Self.ground, in: RoundedRectangle(cornerRadius: Self.cardRadius))
        // The card draws its own ground, so the system's default material
        // behind it would double the chrome — tinted to the ground's edge,
        // beside the ground that decides it.
        .activityBackgroundTint(Self.groundEdge)
        // The ground above is fixed and dark, but the label's system inks and
        // the controls' glass still adapt to the lock screen's appearance — in
        // the light appearance that is near-black words on near-black water.
        // Forcing the subtree dark keeps them on the variants this ground was
        // built against; the in-app player carries the same line.
        .environment(\.colorScheme, .dark)
    }
}
