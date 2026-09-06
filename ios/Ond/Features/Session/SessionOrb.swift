import OndKit
import OndStyle
import OndUI
import SwiftUI

struct SessionOrb: View {
    let beat: SessionTimeline.Beat?
    let frame: AirOrbMotion.Frame
    let extent: CGFloat
    let seed: Float

    private static let tailReach = 74.0 / 300
    private static let tailFill = LinearGradient(
        colors: [Theme.Breath.inhale.opacity(0.75), Theme.Breath.inhale.opacity(0)],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        ZStack {
            SmokeOrb(scale: frame.scale, swirl: frame.swirl, side: extent, sessionSeed: seed)
            if let side = beat?.passage?.side {
                tail(towards: side)
            }
        }
        .frame(width: extent, height: extent)
        .accessibilityHidden(true)
    }

    private func tail(towards side: Passage.Side) -> some View {
        let length = extent * Self.tailReach
        let outward: CGFloat = side == .left ? -1 : 1

        return Capsule()
            .fill(Self.tailFill)
            .frame(width: length, height: 2)
            .rotationEffect(.degrees(side == .left ? 180 : 0))
            .offset(x: outward * length / 2)
    }
}
