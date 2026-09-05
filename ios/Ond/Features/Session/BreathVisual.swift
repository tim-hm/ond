import OndKit
import OndStyle
import OndUI
import SwiftUI

struct BreathVisual: View {
    let beat: SessionTimeline.Beat?
    let elapsed: Duration
    let motion: AirOrbMotion
    let accent: Color
    let register: CopyRegister

    static let extent: CGFloat = 300

    static func drawsArc(reduceMotion: Bool, _ settings: SessionSettings) -> Bool {
        settings.breathVisual.drawn(underReduceMotion: reduceMotion) == .sweeping
    }

    @Environment(SessionSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mostShrink: CGFloat = 0.52
    @ScaledMetric(relativeTo: .largeTitle) private var grown: CGFloat = BreathVisual.extent

    /// Give the guide's space to larger text without enlarging it for smaller text.
    private var fitted: CGFloat {
        Self.extent * min(max(Self.extent / grown, Self.mostShrink), 1)
    }

    var body: some View {
        let fitted = fitted
        let drawsArc = Self.drawsArc(reduceMotion: reduceMotion, settings)

        return Group {
            if drawsArc {
                sweeping(extent: fitted)
                    .accessibilityIdentifier("breath-guide-ring")
            } else if register == .playful {
                PlayfulBreathVisual(
                    kind: beat?.kind,
                    level: level,
                    tint: tint,
                    extent: fitted
                )
                .padding(Theme.Spacing.close)
                .animation(.easeInOut(duration: 0.4), value: isStill)
                .accessibilityIdentifier("breath-guide-playful")
            } else {
                orb(travels: true, extent: fitted)
                    .accessibilityIdentifier("breath-guide-orb")
            }
        }
        .frame(width: fitted, height: fitted)
    }

    private var tint: Color {
        isStill ? Theme.Breath.hold : accent
    }

    private var isStill: Bool {
        beat?.kind.isHold ?? false
    }

    private func sweeping(extent: CGFloat) -> some View {
        ZStack {
            orb(travels: false, extent: extent)
            PhaseArc(
                fraction: beat?.fraction(at: elapsed) ?? 0,
                tint: tint,
                lineWidth: extent * 0.025
            )
            .padding(extent * 0.02)
            .animation(.easeInOut(duration: 0.4), value: isStill)
        }
    }

    private func orb(travels: Bool, extent: CGFloat) -> some View {
        SessionOrb(
            beat: beat,
            frame: motion.frame(at: elapsed, stationary: !travels),
            coreTravels: travels,
            extent: extent
        )
    }

    private var level: Double {
        SessionTimeline.Beat.level(
            ofFullness: beat?.lungFullness(at: elapsed) ?? SessionTimeline.Beat.emptyLungs
        )
    }
}
