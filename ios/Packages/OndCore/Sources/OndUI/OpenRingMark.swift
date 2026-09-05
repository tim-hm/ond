import SwiftUI

public struct OpenRingMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let capArc = 180 * OpenRingGeometry.stroke / (Double.pi * OpenRingGeometry.radius)
        let half = Angle(degrees: (OpenRingGeometry.gap + capArc) / 2)
        let arc = Path {
            $0.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: side * OpenRingGeometry.radius,
                startAngle: .degrees(OpenRingGeometry.opening) + half,
                endAngle: .degrees(OpenRingGeometry.opening) - half,
                clockwise: false
            )
        }
        return arc.strokedPath(StrokeStyle(
            lineWidth: side * OpenRingGeometry.stroke,
            lineCap: .round
        ))
    }
}
