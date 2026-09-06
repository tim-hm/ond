import SwiftUI

struct SmokeOrb: View {
    static let diameterFraction = 1.08

    let scale: Double
    let swirl: Double
    let side: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var seed = Float.random(in: 0 ... 100)

    private static let function = ShaderFunction(library: .default, name: "breathingSmoke")

    var body: some View {
        let width = side * 1.45
        let height = side * 1.35

        Color.clear
            .frame(width: side, height: side)
            .overlay {
                Rectangle()
                    .fill(.white)
                    .frame(width: width, height: height)
                    .colorEffect(Shader(function: Self.function, arguments: [
                        .float2(width, height),
                        .float(swirl * 4),
                        .float(side * scale * Self.diameterFraction / 2),
                        .float(colorScheme == .dark ? 1 : 0),
                        .float(seed),
                    ]))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
