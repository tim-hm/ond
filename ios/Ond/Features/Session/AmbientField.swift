import OndUI
import SwiftUI

/// The slow light behind a live session: one large radial of the inhale's
/// colour, hung just above centre, turning full circle every 46 seconds and
/// swelling a twelfth on the way round. Slow enough to be felt, not watched —
/// the breath is the only thing on this screen that moves at breath speed.
///
/// Takes the moment to draw rather than running a clock of its own, so the
/// surrounding `TimelineView` decides the frame rate and the pause behaviour:
/// ambience is not the breath, so it rides the restful cap, freezes with the
/// session, and holds still under Reduce Motion by being handed one unmoving
/// date.
struct AmbientField: View {
    /// The instant being drawn. Pass a constant to hold the field still.
    let date: Date

    /// How often the field redraws — its own cadence, below the restful cap:
    /// a 46-second turn moves the light a couple of points a tick even at
    /// this rate, and every tick composites a full-screen layer.
    static let frameInterval: Double = 1.0 / 10

    /// One full turn of the field.
    private static let turn: TimeInterval = 46

    /// The field's diameter — fixed rather than a screen ratio, as one cloud
    /// of light larger than any phone; the overflow is the point.
    private static let diameter: CGFloat = 760

    /// How far the field swells at the halfway point of a turn.
    private static let swell = 0.08

    /// Where the field hangs: a touch above centre, which is what makes the
    /// turn visible at all — a centred radial rotates into itself.
    private static let seat = UnitPoint(x: 0.5, y: 0.46)

    var body: some View {
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: Self.turn) / Self.turn

        GeometryReader { proxy in
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Theme.Breath.inhale.opacity(0.16), location: 0),
                            .init(color: Theme.Breath.inhale.opacity(0), location: 0.6),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: Self.diameter / 2
                    )
                )
                .frame(width: Self.diameter, height: Self.diameter)
                .position(
                    x: proxy.size.width * Self.seat.x,
                    y: proxy.size.height * Self.seat.y
                )
                .scaleEffect(1 + Self.swell * sin(.pi * phase))
                // About the screen's centre, not the field's own — the seat
                // above centre is what turns rotation into a visible orbit.
                .rotationEffect(.degrees(phase * 360))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
