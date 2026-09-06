import SwiftUI

enum GardenAir {
    static func draw(
        in context: inout GraphicsContext,
        side: CGFloat,
        time: Double,
        breeze: Double,
        fullness: Double
    ) {
        for index in 0 ..< 18 {
            let seed = Double(index) * 2.39996
            let travel = (time * 0.09 + Double(index) / 18).truncatingRemainder(dividingBy: 1)
            let x = (0.5 + sin(seed + travel * 2.0) * 0.35) * side
            let y = (0.75 - travel * 0.65) * side
            let radius = side * (index.isMultiple(of: 3) ? 0.004 : 0.0025)
            let opacity = sin(travel * .pi) * (0.12 + fullness * 0.22)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 1, green: 0.88, blue: 0.63).opacity(opacity))
            )
        }

        for index in 0 ..< 3 {
            let drift = sin(time * 1.1 + Double(index)) * 0.018
            let y = 0.47 + Double(index) * 0.055 + drift
            var current = Path()
            current.move(to: CGPoint(x: side * 0.12, y: side * (y + 0.08)))
            current.addCurve(
                to: CGPoint(x: side * 0.86, y: side * (y - 0.05)),
                control1: CGPoint(x: side * 0.40, y: side * (y - 0.18)),
                control2: CGPoint(x: side * 0.51, y: side * (y + 0.14))
            )
            context.stroke(current, with: .linearGradient(
                Gradient(colors: [
                    .clear,
                    Color(red: 0.70, green: 0.86, blue: 0.90).opacity(breeze * 0.17),
                    .clear,
                ]),
                startPoint: CGPoint(x: side * 0.12, y: 0),
                endPoint: CGPoint(x: side * 0.86, y: 0)
            ), style: StrokeStyle(lineWidth: side * 0.007, lineCap: .round))
        }
    }
}
