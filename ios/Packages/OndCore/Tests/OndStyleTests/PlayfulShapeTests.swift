import CoreGraphics
import Foundation
@testable import OndStyle
import Testing

/// The flower and the candle flame, held to the claims their doc comments
/// make. Both were tuned by eye over a rendered sweep — the right way to pick
/// them, no way to keep them. Pinned is not how they look but what the
/// surrounding view assumes: the bud is a circle at rest, an open flower
/// still fits the sphere's bounds, and a flame is closed inside its own rect.
@Suite("The shapes a playful breath is drawn with")
struct PlayfulShapeTests {
    private static let box = CGRect(x: 0, y: 0, width: 260, height: 260)

    /// How finely a radius is measured. Every tolerance below is a multiple of
    /// it, because a ray march can only ever answer to within one step and a
    /// tolerance written as a bare number goes stale the moment this changes.
    private static let resolution = 260.0 / 500

    /// The radius at `angle`, measured off the rendered path rather than
    /// recomputed — a test that re-derived the polar curve would agree with a
    /// broken one.
    private static func radius(of shape: PetalShape, at angle: Double) -> Double {
        let centre = CGPoint(x: box.midX, y: box.midY)
        let ray = CGPoint(
            x: centre.x + box.width * cos(angle),
            y: centre.y + box.height * sin(angle)
        )
        // Walk out along the ray to the last point still inside the path.
        let step = resolution
        var reach = 0.0
        let path = shape.path(in: box)

        while reach < box.width {
            let next = reach + step
            let point = CGPoint(
                x: centre.x + next / box.width * (ray.x - centre.x),
                y: centre.y + next / box.height * (ray.y - centre.y)
            )
            if !path.contains(point) {
                break
            }
            reach = next
        }

        return reach
    }

    /// A bud at rest is round. The view leans on this: it scales the same shape
    /// down at the bottom of a breath rather than swapping to a circle, so an
    /// unopened flower that was not a circle would show its petals at the moment
    /// the drawing is meant to be at its calmest.
    @Test("A closed bud is a circle")
    func aClosedBudIsRound() {
        let bud = PetalShape(openness: 0)
        let radii = stride(from: 0.0, to: 2 * .pi, by: .pi / 12).map {
            Self.radius(of: bud, at: $0)
        }

        let smallest = radii.min() ?? 0
        let largest = radii.max() ?? 0

        #expect(largest - smallest <= 2 * Self.resolution, "a closed bud should not lobe")
    }

    /// An open flower reaches exactly as far as the closed one, and no further.
    /// The load-bearing claim in `PetalShape`'s doc, and the reason the petals
    /// grow by cutting valleys rather than by extending tips: the guide is drawn
    /// inside a session ring with only `Theme.Spacing.close` between them, so a
    /// flower that outgrew its bud would cross it.
    @Test("Opening the flower cuts valleys rather than growing tips")
    func anOpenFlowerKeepsItsBounds() {
        let bud = PetalShape(openness: 0)
        let open = PetalShape(openness: 1)

        // A tip sits on a multiple of a sixth of a turn, a valley between two.
        let tip = Self.radius(of: open, at: 0)
        let valley = Self.radius(of: open, at: .pi / Double(PetalShape.petals))
        let closed = Self.radius(of: bud, at: 0)
        let tolerance = 2 * Self.resolution

        #expect(abs(tip - closed) <= tolerance, "a petal tip should reach the bud's own rim")
        #expect(valley < tip, "an open flower should have valleys between its petals")

        // 1 - 2 * depth of the tip, which is what `petalDepth` claims.
        let expected = closed * (1 - 2 * PetalShape.petalDepth)
        #expect(abs(valley - expected) <= tolerance, "the valleys should cut in by petalDepth")
    }

    /// Six of them, counted off the drawing. Counted as upward crossings of the
    /// halfway mark between valley and tip rather than as local maxima: a ray
    /// march quantises the radius, so a lobe's rounded top comes back as a
    /// plateau and peak-finding counts every point on it. A crossing happens once
    /// per lobe however coarsely it is sampled.
    @Test("An open flower has six petals")
    func anOpenFlowerHasSixPetals() {
        let open = PetalShape(openness: 1)
        let samples = 720
        let radii = (0 ..< samples).map {
            Self.radius(of: open, at: Double($0) / Double(samples) * 2 * .pi)
        }

        let middle = ((radii.min() ?? 0) + (radii.max() ?? 0)) / 2
        let crossings = (0 ..< samples).count { index in
            radii[(index + samples - 1) % samples] <= middle && radii[index] > middle
        }

        #expect(crossings == PetalShape.petals)
    }

    /// A flame is a closed shape that stays inside the box it is given, which is
    /// what lets the view size it by frame and scale it from its foot without
    /// anything spilling past the drawing's own bounds.
    @Test("The flame is closed and stays inside its rect")
    func theFlameFitsItsRect() {
        let path = FlameShape().path(in: Self.box)

        #expect(!path.isEmpty)
        #expect(Self.box.insetBy(dx: -1, dy: -1).contains(path.boundingRect))
        // A tip at the top and a foot at the bottom: the shape fills its rect
        // rather than floating in a corner of it.
        #expect(path.boundingRect.height >= Self.box.height * 0.9)
    }
}
