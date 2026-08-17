import Foundation
@testable import OndUI
import Testing

/// The app icon's layers are the palette's third hand-kept mirror, after the
/// app catalogue's `AccentColor` and the marketing stylesheet: Icon Composer
/// fills a layer's path outright rather than tinting it, so each appearance
/// carries the brand as a hex of its own inside an SVG nothing else reads.
///
/// Only exact token restatements are pinned — the ring strokes, and each
/// ground's opening stop. The glow gradients' interior stops are drawn art on
/// the same terms as the session sphere's, and pinning them would fail the day
/// somebody improves a gradient rather than the day one drifts.
@Suite("Icon palette mirror")
struct IconPaletteTests {
    private static let assets = ColorSet.iosDirectory
        .appending(path: "Ond/AppIcon.icon/Assets")

    @Test("each ring strokes the brand for its appearance")
    func ringsCarryTheBrand() throws {
        let brand = try #require(try ColorSet(at: ColorSet.palette, named: "Accent/Brand"))

        try expectOnlyHex(in: "RingLight.svg", is: brand.light?.color)
        try expectOnlyHex(in: "RingDark.svg", is: brand.dark?.color)
    }

    /// Each tile opens on a surface token — light on `Surface/Raised` (the
    /// refresh made the light tile's centre pure white, which is the raised
    /// surface, not the ground), dark on `Surface/Ground` (the refresh made
    /// the dark tile's centre exactly the ground). The vignette's outer stops
    /// are drawn art on the glow gradients' terms: darker than any surface
    /// token on the dark tile, cooler than `raised` on the light one, and
    /// pinning either would fail the day somebody improves the vignette
    /// rather than the day a token drifts.
    @Test("each ground's vignette opens on its surface token")
    func groundsOpenOnTheirSurfaceTokens() throws {
        let ground = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))
        let raised = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceRaised.rawValue
        ))

        let light = try hexes(in: "GroundLight.svg")
        let dark = try hexes(in: "GroundDark.svg")

        try expectHex(#require(light.first), is: raised.light?.color, "GroundLight first stop")
        try expectHex(#require(dark.first), is: ground.dark?.color, "GroundDark first stop")
    }

    /// Every `#rrggbb` in one layer SVG, in document order.
    private func hexes(in file: String) throws -> [String] {
        let svg = try String(
            contentsOf: Self.assets.appending(path: file),
            encoding: .utf8
        )
        return svg.matches(of: /#([0-9a-fA-F]{6})/).map { String($0.output.1) }
    }

    private func expectOnlyHex(in file: String, is expected: CatalogueColor?) throws {
        let found = try hexes(in: file)

        #expect(found.count == 1, "\(file) should state exactly one colour")
        try expectHex(#require(found.first), is: expected, file)
    }

    /// Exact at 8-bit — both sides are hand-written hex, so there is no
    /// mix-rounding to tolerate the way `SitePaletteTests` must.
    private func expectHex(_ stated: String, is expected: CatalogueColor?, _ label: String) throws {
        let catalogue = try #require(expected)
        let value = try #require(Int(stated, radix: 16))

        for (name, shift) in [("red", 16), ("green", 8), ("blue", 0)] {
            let statedChannel = (value >> shift) & 0xFF
            let expectedChannel = try #require(catalogue.channel(name)) * 255

            #expect(
                Double(statedChannel) == expectedChannel,
                """
                \(label): the layer states #\(stated) but the catalogue's \(name) \
                channel is \(Int(expectedChannel.rounded()))
                """
            )
        }
    }
}
