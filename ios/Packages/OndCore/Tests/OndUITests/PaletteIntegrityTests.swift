@testable import OndUI
import Testing

/// The catalogue's failure modes are all silent ones. A `ColorToken` whose name
/// no longer matches an asset resolves to black, because `Color(_:bundle:)` is
/// not failable; a colourset missing its dark entry looks right all day and
/// unreadable at night. Neither is a compile error and neither is a crash, so
/// they are checked here.
///
/// Read off the catalogue on disk rather than a resolved `Color`, for the reason
/// `ColorSet` documents.
@Suite("Palette integrity")
struct PaletteIntegrityTests {
    /// Both directions at once: the token names a colourset, and that colourset
    /// was drawn for both appearances. Every colour in this palette is tuned per
    /// appearance, so one entry — or two carrying the same value — is a mistake
    /// rather than a choice.
    @Test(
        "every token names a colourset drawn for both appearances",
        arguments: ColorToken.allCases
    )
    func tokenAdaptsToAppearance(_ token: ColorToken) throws {
        let colorSet = try #require(
            try ColorSet(at: ColorSet.palette, named: token.rawValue),
            "\(token.rawValue) is missing from Colors.xcassets"
        )

        #expect(colorSet.dark != nil, "\(token.rawValue) has no dark entry")
        #expect(
            colorSet.dark?.color != colorSet.light?.color,
            "\(token.rawValue) is the same colour in both appearances"
        )
    }

    /// The other direction: a colourset nothing names is dead weight at best,
    /// and at worst the survivor of a rename that left the token pointing at
    /// nothing.
    @Test("every colourset in the catalogue is named by a token")
    func catalogueHasNoOrphans() throws {
        let named = Set(ColorToken.allCases.map(\.rawValue))
        let filed = try ColorSet.namesInCatalogue(at: ColorSet.palette)

        #expect(!filed.isEmpty)
        #expect(filed.subtracting(named).isEmpty)
    }

    /// watchOS resolves the Any slot rather than an appearance, so each token
    /// carries a hand-copied watch entry holding its dark value. A hand copy is
    /// a thing that drifts, and the drift shows up as light-mode ink on an
    /// always-black screen — on the device with no way to change the setting.
    @Test("every token's watch entry carries its dark value", arguments: ColorToken.allCases)
    func watchMirrorsTheDarkAppearance(_ token: ColorToken) throws {
        let colorSet = try #require(try ColorSet(at: ColorSet.palette, named: token.rawValue))

        #expect(
            colorSet.watch?.color == colorSet.dark?.color,
            "\(token.rawValue)'s watch entry does not match its dark entry"
        )
    }

    /// The app's own catalogue carries one colour, `AccentColor`, because the
    /// system tints its controls from an asset in the app bundle and cannot read
    /// a package's. That makes it a hand-kept copy of `Accent/Brand`, and the app
    /// target has no test bundle — so this is the only place that can see both
    /// files and notice when someone retunes one of them.
    @Test("the app's global accent still matches the palette's brand")
    func appAccentMirrorsTheBrand() throws {
        let brand = try #require(try ColorSet(at: ColorSet.palette, named: "Accent/Brand"))
        let appAccent = try #require(try ColorSet(at: ColorSet.appCatalogue, named: "AccentColor"))

        #expect(appAccent.light?.color == brand.light?.color)
        #expect(appAccent.dark?.color == brand.dark?.color)
    }
}
