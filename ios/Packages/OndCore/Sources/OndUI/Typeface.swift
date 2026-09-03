import CoreText
import SwiftUI

public extension Theme {
    /// The display face — Newsreader Light, bundled here so every process ships
    /// the same serif. Display only: the wordmark, a screen's one headline, the
    /// phase word — never a control label or body copy. The 16pt text cut
    /// (opsz 16, wght 300), drawn for the 22 to 49pt these roles use. Its
    /// x-height is 0.86 of the 72pt cut's, so every display size is compensated.
    enum Typeface {
        /// The PostScript name registration makes resolvable.
        /// `TypefaceTests` pins it against the TTF on disk, because a font
        /// that fails to resolve falls back to SF silently.
        static let postScriptName = "Newsreader16pt-Light"

        /// Makes the face resolvable in this process. Idempotent, and called
        /// by every composition root — the Live Activity extension is its own
        /// process and draws the phase word too. Registration rather than an
        /// `UIAppFonts` key because the file ships once, in this package's
        /// bundle; a plist key can only name a font copied into each app.
        public static func register() {
            _ = registration
        }

        /// The display face at `size`. `displaySerif(size:)` is how a view
        /// reaches it, and `Wordmark` is how the name does.
        static func display(size: CGFloat) -> Font {
            register()
            return Font.custom(postScriptName, size: size)
        }

        /// One-shot registration. A `static let` because dispatching through
        /// it is what makes `register()` safe to call from every root and
        /// every accessor without re-registering.
        private static let registration: Void = {
            let fonts = Bundle.module.url(forResource: "Fonts", withExtension: nil)

            guard
                let url = fonts?.appending(path: "Newsreader16pt-Light.ttf"),
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            else {
                // Nothing to throw to: a failed registration falls back to
                // SF at the call sites, and `TypefaceTests` is what catches
                // the file going missing before this ever runs.
                return
            }
        }()
    }
}

public extension View {
    /// A display-face role, scaled with Dynamic Type but bounded — the serif
    /// counterpart of `displayNumeral(size:design:)`, with the same cap for the
    /// same reason. `size` is the size at the default Dynamic Type setting.
    func displaySerif(size: CGFloat) -> some View {
        modifier(DisplaySerif(base: size))
    }
}

/// The scaling half of `displaySerif(size:)`, a `ViewModifier` because
/// `ScaledMetric` reads the environment and so has to live on something
/// SwiftUI instantiates.
private struct DisplaySerif: ViewModifier {
    let base: CGFloat

    /// `base` grown by the reader's Dynamic Type setting, against
    /// `.largeTitle` for `DisplayNumeral`'s reason: display text grows on the
    /// same curve as the copy beside it.
    @ScaledMetric private var scaled: CGFloat

    /// The same growth bound `DisplayNumeral` holds, because the two roles
    /// share a screen and must stop growing at the same step.
    private static let mostGrowth: CGFloat = 1.4

    init(base: CGFloat) {
        self.base = base
        _scaled = ScaledMetric(wrappedValue: base, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        content.font(Theme.Typeface.display(size: min(scaled, base * Self.mostGrowth)))
    }
}
