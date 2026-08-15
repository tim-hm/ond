import Foundation
@testable import OndUI
import Testing

/// `Theme.swift` promises that the app's palette is the marketing site's, and
/// the site cannot import the catalogue any more than the catalogue can read a
/// stylesheet — so for as long as nothing measured the pair, the promise was
/// only a comment. It broke exactly that way once: the brand moved from teal
/// to sea blue and `web/style.css` kept stroking the old accent for months.
/// This suite is the only place that can see both files.
@Suite("Site palette mirror")
struct SitePaletteTests {
    /// The tokens the stylesheet restates verbatim, by their CSS custom
    /// property and the catalogue entry each mirrors. `ColorToken` cases, not
    /// name strings, for the enum's own reason: a renamed colourset should
    /// fail here at compile time, not as a nil catalogue at run time.
    private static let statedPairs: [(property: String, token: ColorToken)] = [
        ("ground", .surfaceGround),
        ("ink", .inkPrimary),
        ("ink-soft", .inkSecondary),
        ("line", .surfaceLine),
        ("accent", .accentBrand),
        ("hold", .accentStill),
    ]

    /// The stylesheet, read and parsed once for the whole run: Swift Testing
    /// makes a fresh suite per case, so an instance property would re-read the
    /// file seven times for one unchanging answer.
    private static let site = Result { try SitePalette() }

    /// The dark exhale gives up 45% where the app's palette-wide ceiling is
    /// 20% — the near-black has room the white does not, and both files
    /// document the disagreement. This constant is the page's half of it.
    private static let darkSoftening = 0.45

    /// The hero orb's fill: the accent softened one step past the exhale
    /// stroke, in both appearances — see the `--orb` comment in the stylesheet.
    private static let orbSoftening = 0.30

    @Test("every stated token matches the catalogue", arguments: statedPairs)
    func statedTokenMatchesTheCatalogue(_ pair: (property: String, token: ColorToken)) throws {
        let site = try Self.site.get()
        let colorSet = try #require(try ColorSet(at: ColorSet.palette, named: pair.token.rawValue))

        try expectMatch(site.light(pair.property), colorSet.light?.color, "\(pair.property), light")
        try expectMatch(site.dark(pair.property), colorSet.dark?.color, "\(pair.property), dark")
    }

    /// The two derived properties, held to the derivation rather than to a
    /// second statement of the result: the exhale is the brand softened by the
    /// app's own ceiling (its 45% dark exception above), and the orb one step
    /// further. Softened through `Color.mix` exactly as `FigureShape` softens,
    /// so the page keeps stating the colour the app draws.
    @Test("the exhale and the orb are the brand, softened as the app softens")
    func derivedTokensFollowTheBrand() throws {
        let site = try Self.site.get()
        let brand = try #require(try ColorSet(at: ColorSet.palette, named: "Accent/Brand"))
        let ground = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))

        let cases: [Derivation] = [
            .init(property: "accent-soft", appearance: .light, fraction: Theme.Softening.strongest),
            .init(property: "accent-soft", appearance: .dark, fraction: Self.darkSoftening),
            .init(property: "orb", appearance: .light, fraction: Self.orbSoftening),
            .init(property: "orb", appearance: .dark, fraction: Self.orbSoftening),
        ]

        for c in cases {
            let full = try #require(brand[c.appearance]?.color)
            let base = try #require(ground[c.appearance]?.color)
            let softened = try #require(full.softened(towards: base, by: c.fraction))
            let stated = c.appearance == .light ? site.light(c.property) : site.dark(c.property)

            try expectMatch(stated, softened, "\(c.property), \(c.appearance.rawValue)")
        }
    }

    /// One derived property to check: which custom property, in which
    /// appearance, softened by how much.
    private struct Derivation {
        let property: String
        let appearance: Appearance
        let fraction: Double
    }

    /// Channel-by-channel at 8-bit precision, which is all a hex can state.
    /// The tolerance of one is for the derived colours: a `Color.mix` result
    /// lands wherever `Float` resolution puts it, and quantising can round a
    /// half-step differently than the hand that wrote the stylesheet did.
    private func expectMatch(
        _ stated: String?,
        _ catalogue: CatalogueColor?,
        _ label: String
    ) throws {
        let hex = try #require(stated, "\(label) is not stated in web/style.css")
        let expected = try #require(catalogue)
        let value = try #require(Int(hex, radix: 16), "\(label) is not a hex colour")

        for (name, shift) in [("red", 16), ("green", 8), ("blue", 0)] {
            let statedChannel = (value >> shift) & 0xFF
            let expectedChannel = try #require(expected.channel(name)) * 255

            #expect(
                abs(Double(statedChannel) - expectedChannel) <= 1,
                """
                \(label): the page states #\(hex) but the catalogue's \(name) \
                channel resolves to \(Int(expectedChannel.rounded()))
                """
            )
        }
    }
}

/// `web/style.css` reduced to its custom properties: every `--name: #rrggbb`
/// in the base `:root` block, and every redefinition inside the
/// `prefers-color-scheme: dark` media block.
private struct SitePalette {
    private let base: [String: String]
    private let overrides: [String: String]

    init() throws {
        let stylesheet = ColorSet.iosDirectory
            .deletingLastPathComponent() // repo root
            .appending(path: "web/style.css")
        let css = try String(contentsOf: stylesheet, encoding: .utf8)

        let halves = css.split(
            separator: "@media (prefers-color-scheme: dark)",
            maxSplits: 1
        )
        base = Self.properties(in: halves.first.map(String.init) ?? "")
        overrides = Self.properties(in: halves.count > 1 ? String(halves[1]) : "")
    }

    /// Nil when the page does not state the property as a hex colour.
    func light(_ property: String) -> String? {
        base[property]
    }

    /// The dark block restates every colour it changes, so a missing override
    /// is a real finding rather than a fallback to the light value.
    func dark(_ property: String) -> String? {
        overrides[property]
    }

    private static func properties(in block: String) -> [String: String] {
        let declarations = block.matches(of: /--([a-z-]+):\s*#([0-9a-fA-F]{6})/)

        return Dictionary(
            declarations.map { (String($0.output.1), String($0.output.2)) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
