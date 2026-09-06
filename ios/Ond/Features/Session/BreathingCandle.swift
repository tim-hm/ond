import SwiftUI

struct BreathingCandle: View {
    let strength: Double
    let breeze: Double
    let time: Double
    let seed: Double
    let companion: Bool
    let width: CGFloat
    let height: CGFloat

    private static let flame = ShaderFunction(library: .default, name: "gardenFlame")

    var body: some View {
        Canvas { context, _ in
            let cream = companion ? Color(red: 0.84, green: 0.79, blue: 0.95) : Color(
                red: 0.98,
                green: 0.87,
                blue: 0.66
            )
            let shadow = companion ? Color(red: 0.37, green: 0.30, blue: 0.49) : Color(
                red: 0.51,
                green: 0.35,
                blue: 0.22
            )
            let wax = CGRect(x: 0, y: 0, width: width, height: height)
            context.fill(
                RoundedRectangle(cornerRadius: width * 0.16).path(in: wax),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: shadow, location: 0),
                        .init(color: cream, location: 0.28),
                        .init(color: cream.opacity(0.95), location: 0.6),
                        .init(color: shadow, location: 1),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: width, y: 0)
                )
            )

            let top = CGRect(x: 0, y: -width * 0.02, width: width, height: width * 0.24)
            context.fill(Path(ellipseIn: top), with: .linearGradient(
                Gradient(colors: [cream, shadow.opacity(0.6)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: width * 0.3)
            ))

            for (x, length) in [(0.22, 0.23), (0.76, 0.14)] {
                let drip = CGRect(
                    x: width * x,
                    y: width * 0.1,
                    width: width * 0.095,
                    height: height * length
                )
                context.fill(Capsule().path(in: drip), with: .color(cream.opacity(0.36)))
            }

            var wick = Path()
            wick.move(to: CGPoint(x: width * 0.5, y: width * 0.11))
            wick.addQuadCurve(
                to: CGPoint(x: width * 0.53, y: -width * 0.12),
                control: CGPoint(x: width * 0.46, y: -width * 0.05)
            )
            context.stroke(
                wick,
                with: .color(Color(red: 0.27, green: 0.17, blue: 0.15)),
                style: StrokeStyle(lineWidth: width * 0.045, lineCap: .round)
            )
        }
        .frame(width: width, height: height)
        .overlay(alignment: .top) {
            let flameWidth = width * 3
            let flameHeight = height * 0.95
            Rectangle()
                .fill(.white)
                .frame(width: flameWidth, height: flameHeight)
                .colorEffect(Shader(function: Self.flame, arguments: [
                    .float2(flameWidth, flameHeight),
                    .float(time),
                    .float(strength),
                    .float(breeze),
                    .float(seed),
                ]))
                .offset(y: -flameHeight * 0.9)
        }
    }
}
