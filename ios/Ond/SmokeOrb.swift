import SwiftUI

struct SmokeOrb: View {
    static let diameterFraction = 0.92

    let scale: Double
    let swirl: Double
    let side: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private static let function = ShaderFunction(library: .default, name: "breathingSmoke")

    var body: some View {
        Rectangle()
            .fill(.white)
            .colorEffect(Shader(function: Self.function, arguments: [
                .float2(side, side),
                .float(swirl * 4),
                .float(scale * Self.diameterFraction),
                .float(colorScheme == .dark ? 1 : 0),
            ]))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
