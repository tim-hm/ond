import Foundation
import Testing

/// The open mark's dash pattern and rotation are worked out by hand from its
/// radius, its stroke and a 60 degree gap. Nothing recomputes them, and a wrong
/// phase draws a correctly sized gap at the wrong angle — which reads as correct
/// in a diff. So the arithmetic is repeated here: retuning the ring stays free,
/// and forgetting to retune the pattern does not.
@Suite("Icon ring geometry")
struct IconGeometryTests {
    /// The gap between the round cap ends, in degrees.
    private static let gap = 60.0

    /// Where that gap centres, clockwise from three o'clock — the point an SVG
    /// circle's path starts at. Lower left, where the breath leaves.
    private static let opening = 135.0

    /// A number rounded to one decimal sits up to half of that from the value
    /// it states.
    private static let slack = 0.05

    private static let files = ["RingLight.svg", "RingDark.svg"]

    private static let assets = ColorSet.iosDirectory
        .appending(path: "Ond/AppIcon.icon/Assets")

    @Test("each ring's dash pattern follows its own radius", arguments: files)
    func dashPatternFollowsTheRadius(file: String) throws {
        let ring = try Ring(in: Self.assets.appending(path: file))
        // Round caps put half a stroke past each dash end, so the drawn gap is
        // the visual gap plus one whole stroke width.
        let gap = ring.circumference * Self.gap / 360 + ring.strokeWidth

        #expect(abs(ring.gap - gap) <= Self.slack, "\(file) gap arc")
        #expect(abs(ring.dash - (ring.circumference - gap)) <= Self.slack, "\(file) dash arc")
    }

    @Test("each ring's rotation carries the opening to the lower left", arguments: files)
    func rotationPlacesTheOpening(file: String) throws {
        let ring = try Ring(in: Self.assets.appending(path: file))
        // The one dash starts at three o'clock, so the gap runs from where the
        // dash ends round to that start, and its centre is halfway between.
        let centre = (360 * ring.dash / ring.circumference + 360) / 2
        let placed = (centre + ring.rotation).truncatingRemainder(dividingBy: 360)

        #expect(abs(placed - Self.opening) < 0.1, "\(file) opening")
    }

    /// Tinted and clear flatten the mark to one luminance, so nothing inside it
    /// may need colour to be read.
    @Test("each ring is a flat stroke with round caps", arguments: files)
    func theMarkIsOneFlatStroke(file: String) throws {
        let svg = try String(
            contentsOf: Self.assets.appending(path: file),
            encoding: .utf8
        )

        #expect(svg.contains(#"stroke-linecap="round""#), "\(file) caps")
        #expect(svg.contains(#"fill="none""#), "\(file) fill")
        #expect(!svg.contains("Gradient"), "\(file) states a gradient")
    }

    /// Icon Composer takes one file per appearance, so the drawing is written
    /// twice. Only the stroke may differ between them.
    @Test("the two rings are one drawing in two colours")
    func bothRingsDrawTheSameMark() throws {
        let drawings = try Self.files.map { file in
            try String(contentsOf: Self.assets.appending(path: file), encoding: .utf8)
                .replacing(/#[0-9a-fA-F]{6}/, with: "")
        }

        #expect(Set(drawings).count == 1)
    }
}

/// The one stroked circle a ring layer draws, read back from the file.
private struct Ring {
    let radius: Double
    let strokeWidth: Double
    let dash: Double
    let gap: Double
    let rotation: Double

    var circumference: Double {
        2 * .pi * radius
    }

    init(in url: URL) throws {
        let svg = try String(contentsOf: url, encoding: .utf8)
        let pattern = try #require(svg.firstMatch(of: /stroke-dasharray="([\d.]+) ([\d.]+)"/))

        radius = try Self.number(in: svg, matching: /\br="([\d.]+)"/)
        strokeWidth = try Self.number(in: svg, matching: /stroke-width="([\d.]+)"/)
        rotation = try Self.number(in: svg, matching: /rotate\((-?[\d.]+)[ )]/)
        dash = try #require(Double(pattern.output.1))
        gap = try #require(Double(pattern.output.2))
    }

    /// Required rather than defaulted: a layer that stopped stating one of
    /// these is a drawing this suite can no longer check.
    private static func number(
        in svg: String,
        matching expression: Regex<(Substring, Substring)>
    ) throws -> Double {
        let match = try #require(svg.firstMatch(of: expression))
        return try #require(Double(match.output.1))
    }
}
