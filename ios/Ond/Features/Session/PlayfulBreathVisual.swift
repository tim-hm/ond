import OndKit
import SwiftUI

struct PlayfulBreathVisual: View {
    let kind: PhaseKind?
    let level: Double
    let progress: Double
    let time: Double
    let extent: CGFloat

    @State private var seed = Double.random(in: 0 ... 20)

    private var breeze: Double {
        kind == .exhale ? sin(.pi * progress) : 0
    }

    private var flameStrength: Double {
        kind == .exhale || kind == .holdOut ? max(0, (level - 0.10) / 0.90) : level
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let glow = CGRect(
                    x: side * 0.05,
                    y: side * 0.18,
                    width: side * 0.9,
                    height: side * 0.78
                )
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.42, green: 0.28, blue: 0.34).opacity(0.14),
                        .clear,
                    ]),
                    center: CGPoint(x: side * 0.5, y: side * 0.55),
                    startRadius: 0,
                    endRadius: side * 0.47
                ))

                GardenFlower(
                    companion: false,
                    center: CGPoint(x: side * 0.28, y: side * 0.29),
                    root: CGPoint(x: side * 0.37, y: side * 0.90),
                    radius: side * 0.23,
                    fullness: level,
                    time: time + seed
                ).draw(in: &context)
                GardenFlower(
                    companion: true,
                    center: CGPoint(x: side * 0.71, y: side * 0.39),
                    root: CGPoint(x: side * 0.66, y: side * 0.91),
                    radius: side * 0.18,
                    fullness: level,
                    time: time + seed + 1.8
                ).draw(in: &context)
                GardenAir.draw(
                    in: &context,
                    side: side,
                    time: time + seed,
                    breeze: breeze,
                    fullness: level
                )
            }

            BreathingCandle(
                strength: flameStrength,
                breeze: breeze,
                time: time,
                seed: seed,
                companion: false,
                width: extent * 0.15,
                height: extent * 0.27
            )
            .position(x: extent * 0.43, y: extent * 0.77)

            BreathingCandle(
                strength: flameStrength,
                breeze: breeze,
                time: time,
                seed: seed + 3.7,
                companion: true,
                width: extent * 0.115,
                height: extent * 0.19
            )
            .position(x: extent * 0.67, y: extent * 0.85)
        }
        .frame(width: extent, height: extent)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
