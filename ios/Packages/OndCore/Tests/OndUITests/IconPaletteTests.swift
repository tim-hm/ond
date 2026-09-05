import Foundation
import Testing

@Suite("Selected icon palette")
struct IconPaletteTests {
    private static let assets = ColorSet.iosDirectory
        .appending(path: "Ond/AppIcon.icon/Assets")
    private static let candidate = ColorSet.iosDirectory.deletingLastPathComponent()
        .appending(path: "docs/design/icons/refined-ring.svg")

    @Test("Both appearances carry the selected ring colour")
    func ringsMatchTheSelectedIcon() throws {
        let approved = try source(Self.candidate)
        let colour = try #require(approved.firstMatch(of: /<g color="#([0-9a-fA-F]{6})"/))
        for file in ["RingLight.svg", "RingDark.svg"] {
            #expect(try hexes(in: file) == [String(colour.output.1)])
        }
    }

    @Test("Both tiles carry the selected flat background")
    func groundsMatchTheSelectedIcon() throws {
        let approved = try source(Self.candidate)
        let colour = try #require(approved.firstMatch(of: /<rect[^>]*fill="#([0-9a-fA-F]{6})"/))
        for file in ["GroundLight.svg", "GroundDark.svg"] {
            #expect(try hexes(in: file) == [String(colour.output.1)])
            #expect(try !source(Self.assets.appending(path: file)).contains("Gradient"))
        }
    }

    private func source(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func hexes(in file: String) throws -> [String] {
        try source(Self.assets.appending(path: file))
            .matches(of: /#([0-9a-fA-F]{6})/).map { String($0.output.1) }
    }
}
