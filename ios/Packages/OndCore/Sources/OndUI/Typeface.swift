import CoreText
import SwiftUI

public extension Theme {
    /// The display face — Newsreader Light, bundled here so every process
    /// that draws with `OndUI` ships the same serif.
    ///
    /// Display only: the wordmark, a screen's one Newsreader headline, and
    /// the phase word inside the breath. Never a control label, never body
    /// copy — everything else is SF Pro through the ordinary text styles.
    ///
    /// The 16pt optical-size cut, one file for every role: the family's
    /// static instances come cut for 6, 16 and 72 points, and the display
    /// cut is tuned for sizes the smallest consumer — the watch's 26pt
    /// phase word, watched mid-breath on a dark screen — never reaches. A
    /// text cut drawn large stays airy at Light weight; a display cut drawn
    /// small shimmers.
    enum Typeface {
        /// The PostScript name registration makes resolvable.
        /// `TypefaceTests` pins it against the TTF on disk, because a font
        /// that fails to resolve falls back to SF silently.
        static let postScriptName = "Newsreader16pt-Light"

        /// Makes the face resolvable in this process. Idempotent, and called
        /// by every composition root — phone, watch, and the Live Activity
        /// extension, which is its own process and draws the phase word too.
        ///
        /// Registration rather than an `UIAppFonts` Info.plist key because
        /// the file ships once, in this package's bundle, where a plist key
        /// can only name a font copied into each app bundle by hand.
        public static func register() {
            _ = registration
        }

        /// The role for "önd" wherever the wordmark appears.
        public static func wordmark(size: CGFloat) -> Font {
            display(size: size)
        }

        /// The role for the phase word inside the breath geometry.
        public static func phaseWord(size: CGFloat) -> Font {
            display(size: size)
        }

        /// The display face at `size`. Prefer the named roles above; this is
        /// the one they share, public for the headline a screen sets in the
        /// display face directly.
        public static func display(size: CGFloat) -> Font {
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
    /// counterpart of `displayNumeral(size:design:)`, with the same cap for
    /// the same reason: display text already holds its share of the screen
    /// at the default size.
    ///
    /// - Parameter size: The size at the default Dynamic Type setting.
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
