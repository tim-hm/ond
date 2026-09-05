import OndStyle
import OndUI
import SwiftUI

struct WatchAirOrb: View {
    let frame: AirOrbMotion.Frame
    let side: CGFloat

    static let designSide: CGFloat = 124

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height) * frame.scale
            let bounds = CGRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            let sphere = Path(ellipseIn: bounds)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            context.fill(sphere, with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.34, green: 0.66, blue: 0.72), location: 0),
                    .init(color: Color(red: 0.09, green: 0.32, blue: 0.40), location: 0.62),
                    .init(color: Color(red: 0.02, green: 0.10, blue: 0.15), location: 1),
                ]),
                center: CGPoint(x: bounds.minX + diameter * 0.36, y: bounds.minY + diameter * 0.28),
                startRadius: 0,
                endRadius: diameter * 0.78
            ))
            context.clip(to: sphere)

            for index in 0 ..< 4 {
                drawCurrent(index, in: &context, bounds: bounds)
            }

            context.fill(sphere, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.35), .cyan.opacity(0.06), .clear]),
                center: CGPoint(x: bounds.minX + diameter * 0.30, y: bounds.minY + diameter * 0.22),
                startRadius: 0,
                endRadius: diameter * 0.48
            ))
            context.fill(sphere, with: .radialGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.74),
                    .init(color: Theme.Breath.inhale.opacity(0.12), location: 0.93),
                    .init(color: .clear, location: 1),
                ]),
                center: center,
                startRadius: 0,
                endRadius: diameter / 2
            ))
        }
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawCurrent(_ index: Int, in context: inout GraphicsContext, bounds: CGRect) {
        let diameter = bounds.width
        let offset = Double(index) * 1.26
        let angle = frame.swirl + offset
        let bend = sin(angle) * 0.22
        let height = 0.18 + Double(index) * 0.18 + cos(angle * 0.7) * 0.08
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: -0.12, y: height))
        ribbon.addCurve(
            to: CGPoint(x: 1.12, y: height + 0.12),
            control1: CGPoint(x: 0.26, y: height - 0.40 + bend),
            control2: CGPoint(x: 0.63, y: height + 0.40 - bend)
        )
        ribbon.addCurve(
            to: CGPoint(x: -0.12, y: height),
            control1: CGPoint(x: 0.56, y: height + 0.16 - bend),
            control2: CGPoint(x: 0.30, y: height - 0.24 + bend)
        )
        ribbon.closeSubpath()

        var layer = context
        layer.translateBy(x: bounds.midX, y: bounds.midY)
        layer.rotate(by: .radians(frame.swirl * 0.55 + Double(index) * 0.24 - 0.45))
        layer.scaleBy(x: diameter, y: diameter)
        layer.translateBy(x: -0.5, y: -0.5)
        layer.blendMode = .screen
        layer.fill(ribbon, with: .linearGradient(
            Gradient(colors: [
                .clear,
                .white.opacity(0.13),
                Theme.Breath.inhale.opacity(0.28),
                .clear,
            ]),
            startPoint: CGPoint(x: 0.2, y: 0.1),
            endPoint: CGPoint(x: 0.75, y: 0.9)
        ))
    }
}
