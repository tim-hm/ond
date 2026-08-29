import CoreText
import Foundation
@testable import OndUI
import Testing

/// The display face's failure mode is the palette's: silent. A missing or renamed
/// font file does not throw — `Font.custom` falls back to SF and the wordmark
/// quietly stops being the wordmark. So the file and the name the code asks for are
/// pinned here, against the source tree for `ColorSet`'s reason: the test bundle's
/// copy is a build-system artefact, and the source is what ships.
@Suite("The display face")
struct TypefaceTests {
    private static let fonts = ColorSet.iosDirectory
        .appending(path: "Packages/OndCore/Sources/OndUI/Resources/Fonts")

    /// The TTF parses under CoreText and answers to exactly the PostScript
    /// name `Theme.Typeface` registers and resolves by. A renamed cut — a
    /// different weight, a different optical size — fails here rather than as
    /// SF on a device.
    @Test("the bundled cut carries the PostScript name the code asks for")
    func bundledFontMatchesTheRegisteredName() throws {
        let url = Self.fonts.appending(path: "\(Theme.Typeface.postScriptName).ttf")
        let descriptors = try #require(
            CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            "no font descriptors at \(url.path)"
        )
        let descriptor = try #require(descriptors.first)
        let name = try #require(
            CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        )

        #expect(name == Theme.Typeface.postScriptName)
    }

    /// OFL 1.1 requires the licence to travel with the font software — in the
    /// package resources beside the TTF, and beside the site's woff2, so
    /// neither copy can ship bare.
    @Test("the licence travels with both font copies")
    func licenceShipsBesideTheFont() {
        let site = ColorSet.iosDirectory
            .deletingLastPathComponent()
            .appending(path: "web/fonts")

        #expect(FileManager.default.fileExists(atPath: Self.fonts.appending(path: "OFL.txt").path))
        #expect(FileManager.default.fileExists(atPath: site.appending(path: "OFL.txt").path))
        #expect(
            FileManager.default.fileExists(
                atPath: site.appending(path: "newsreader-light.woff2").path
            )
        )
    }
}
