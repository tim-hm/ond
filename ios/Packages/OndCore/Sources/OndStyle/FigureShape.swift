import OndKit
import OndUI
import SwiftUI

/// A technique figure's strokes as SwiftUI paths, and the palette they resolve
/// in. In `OndStyle` because both apps draw these and only this target may know
/// a domain type and a design token at once. The fit stays in `OndKit`'s
/// `TechniqueFigure.transform(into:inset:)`, so the site's generator applies the
/// same rule — a second copy is the divergence `check:diagrams` cannot catch.
public struct FigureShape: Shape {
    public let commands: [TechniqueFigure.Command]
    /// The whole figure's extent, so every stroke of one drawing shares a
    /// transform and the baseline still lines up under the curve.
    public let bounds: CGRect
    /// The weight this figure is stroked at, so the fit can leave room for it.
    public let lineWidth: CGFloat

    public init(commands: [TechniqueFigure.Command], bounds: CGRect, lineWidth: CGFloat) {
        self.commands = commands
        self.bounds = bounds
        self.lineWidth = lineWidth
    }

    public func path(in rect: CGRect) -> Path {
        // Placed as each point is added rather than by transforming the finished
        // path: SwiftUI calls this on every layout pass for every stroke of
        // every visible figure, and `applying` walks the whole path a second
        // time to build a second one.
        let fit = TechniqueFigure.transform(fitting: bounds, into: rect, lineWidth: lineWidth)
        var path = Path()

        for command in commands {
            switch command {
            case let .move(point):
                path.move(to: point.applying(fit))
            case let .line(point):
                path.addLine(to: point.applying(fit))
            case let .curve(point, control1, control2):
                path.addCurve(
                    to: point.applying(fit),
                    control1: control1.applying(fit),
                    control2: control2.applying(fit)
                )
            }
        }

        return path
    }
}

public extension TechniqueFigure.Ink {
    /// The exhale softens the accent towards the ground, not a second hue — two hues
    /// went muddy on warm accents and collided on calm. `Theme.Softening.strongest` is
    /// the fraction: soft and 3:1 are one decision, measured on this stroke — do not
    /// raise or split it per appearance. Ratios hold over `Theme.Surface.ground` only;
    /// `figureGround()` restores it under `accentGround(_:)`. See `ThemeColorTests`.
    func colour(on accent: Color) -> Color {
        switch self {
        case .inhale: accent
        case .exhale: accent.mix(with: Theme.Surface.ground, by: Theme.Softening.strongest)
        case .hold: Theme.Breath.hold
        // The site draws its baselines at 40% of the body ink. Here that is the
        // palette's own faintest step, which already resolves per appearance.
        case .baseline: Theme.Ink.tertiary.opacity(0.5)
        }
    }
}
