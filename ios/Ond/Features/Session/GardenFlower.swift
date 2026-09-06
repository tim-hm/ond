import SwiftUI

struct GardenFlower {
    let companion: Bool
    let center: CGPoint
    let root: CGPoint
    let radius: CGFloat
    let fullness: Double
    let time: Double

    func draw(in context: inout GraphicsContext) {
        drawStem(in: &context)
        var bloom = context
        bloom.translateBy(x: crown.x, y: crown.y)
        bloom.rotate(by: .radians(sin(time * 0.28) * 0.035))
        drawPetals(in: &bloom)
        drawHeart(in: &bloom)
    }

    private var crown: CGPoint {
        CGPoint(
            x: center.x + sin(time * 0.55) * radius * 0.055,
            y: center.y + cos(time * 0.37) * radius * 0.025
        )
    }

    private func drawStem(in context: inout GraphicsContext) {
        let stem = Color(red: 0.28, green: 0.55, blue: 0.40)
        var stalk = Path()
        stalk.move(to: root)
        stalk.addCurve(
            to: crown,
            control1: CGPoint(x: root.x - radius * 0.1, y: root.y - radius * 0.8),
            control2: CGPoint(x: crown.x + radius * 0.20, y: crown.y + radius * 0.65)
        )
        context.stroke(
            stalk,
            with: .color(stem),
            style: StrokeStyle(lineWidth: radius * 0.055, lineCap: .round)
        )

        for index in 0 ..< 2 {
            let direction: CGFloat = index == 0 ? -1 : 1
            let origin = CGPoint(x: root.x, y: root.y - radius * (0.55 + CGFloat(index) * 0.45))
            var leaf = Path()
            leaf.move(to: origin)
            let tip = CGPoint(x: origin.x + direction * radius * 0.74, y: origin.y - radius * 0.53)
            leaf.addQuadCurve(to: tip, control: CGPoint(x: tip.x, y: origin.y + radius * 0.05))
            leaf.addQuadCurve(
                to: origin,
                control: CGPoint(x: origin.x - direction * radius * 0.07, y: tip.y)
            )
            context.fill(leaf, with: .linearGradient(
                Gradient(colors: [Color(red: 0.47, green: 0.73, blue: 0.49), stem.opacity(0.55)]),
                startPoint: tip,
                endPoint: origin
            ))
        }
    }

    private func drawPetals(in bloom: inout GraphicsContext) {
        let opening = 0.70 + fullness * 0.30
        let rose = companion ? Color(red: 0.60, green: 0.42, blue: 0.79) : Color(
            red: 0.85,
            green: 0.36,
            blue: 0.42
        )
        let cream = companion ? Color(red: 0.88, green: 0.80, blue: 0.99) : Color(
            red: 1,
            green: 0.79,
            blue: 0.66
        )

        for layer in 0 ..< 2 {
            for index in 0 ..< 9 {
                var petalContext = bloom
                petalContext
                    .rotate(by: .radians(Double(index) * .pi * 2 / 9 + Double(layer) * .pi / 9))
                let length = radius * opening * (layer == 0 ? 1 : 0.74)
                let breadth = radius * (0.27 + fullness * 0.11)
                var petal = Path()
                petal.move(to: CGPoint(x: 0, y: radius * 0.07))
                petal.addCurve(
                    to: CGPoint(x: 0, y: -length),
                    control1: CGPoint(x: -breadth, y: -length * 0.24),
                    control2: CGPoint(x: -breadth, y: -length * 1.10)
                )
                petal.addCurve(
                    to: CGPoint(x: 0, y: radius * 0.07),
                    control1: CGPoint(x: breadth, y: -length * 1.10),
                    control2: CGPoint(x: breadth, y: -length * 0.24)
                )
                petal.closeSubpath()
                petalContext.fill(petal, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: cream, location: 0),
                        .init(color: rose.opacity(0.94), location: 0.62),
                        .init(color: rose.opacity(0.45), location: 1),
                    ]),
                    startPoint: CGPoint(x: -breadth * 0.3, y: -length),
                    endPoint: CGPoint(x: breadth * 0.3, y: radius * 0.1)
                ))
                petalContext.stroke(
                    petal,
                    with: .color(cream.opacity(0.24)),
                    lineWidth: radius * 0.009
                )
            }
        }
    }

    private func drawHeart(in bloom: inout GraphicsContext) {
        let heart = CGRect(
            x: -radius * 0.22,
            y: -radius * 0.22,
            width: radius * 0.44,
            height: radius * 0.44
        )
        bloom.fill(Path(ellipseIn: heart), with: .radialGradient(
            Gradient(colors: [
                Color(red: 1, green: 0.91, blue: 0.58),
                Color(red: 0.75, green: 0.43, blue: 0.18),
            ]),
            center: CGPoint(x: -radius * 0.07, y: -radius * 0.07),
            startRadius: 0,
            endRadius: radius * 0.30
        ))
        for index in 0 ..< 21 {
            let angle = Double(index) * 2.39996
            let distance = sqrt(Double(index) / 21) * radius * 0.17
            let dot = CGRect(
                x: cos(angle) * distance,
                y: sin(angle) * distance,
                width: radius * 0.025,
                height: radius * 0.025
            )
            bloom.fill(Path(ellipseIn: dot), with: .color(Color.white.opacity(0.55)))
        }
    }
}
