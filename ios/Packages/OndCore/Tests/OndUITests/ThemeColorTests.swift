import Foundation
@testable import OndUI
import Testing

/// Every contrast this palette has to hold, measured from the catalogue rather
/// than judged by eye. Whether the catalogue behind it is well-formed at all —
/// every token naming a colourset, every colourset drawn twice — is
/// `PaletteIntegrityTests`.
///
/// Every ratio is computed from the catalogue on disk rather than a resolved
/// `Color`, for the reason `ColorSet` documents.
@Suite("Theme colours")
struct ThemeColorTests {
    /// Every ink is drawn on one of the two grounds, and every one of them
    /// carries `.caption`, `.caption2` or `.footnote` copy somewhere — so the
    /// bar is AA's 4.5:1 for normal text throughout, with no large-text
    /// allowance to fall back on.
    ///
    /// Measured from the catalogue rather than checked by eye because the
    /// failure this replaced was invisible: `Ink/Tertiary` sat at 2.72:1 in the
    /// light appearance for as long as it shipped, and looked like a design
    /// choice.
    @Test(
        "every ink clears WCAG AA on every ground, on every surface",
        arguments: inks,
        grounds
    )
    func inkIsLegibleOnEveryGround(_ ink: ColorToken, _ ground: ColorToken) throws {
        let inkSet = try #require(try ColorSet(at: ColorSet.palette, named: ink.rawValue))
        let groundSet = try #require(try ColorSet(at: ColorSet.palette, named: ground.rawValue))

        for appearance in Appearance.allCases {
            let foreground = try #require(inkSet[appearance]?.color)
            let background = try #require(groundSet[appearance]?.color)

            try expectAA(
                foreground,
                on: background,
                "\(ink.rawValue) on \(ground.rawValue)",
                appearance
            )
        }
    }

    /// The strengths an accent wash carries a word at. 0.15 is `GoalBadge`;
    /// `Theme.Fill.selection` is an opaque control drawn as chosen — a
    /// schedule's weekday, the coach's selected reply; 0.30 is a selected
    /// `FilterPill`, which deepens the fill rather than moving the word into
    /// the accent.
    private static let washes = [0.15, Theme.Fill.selection, 0.3]

    /// A badge sets a word in primary ink over a wash of an accent —
    /// `GoalBadge` is the one that names a technique's goal, and `FilterPill`
    /// the one you can press. Drawn the obvious way instead, with the accent
    /// carrying the text, four of the five goal accents miss AA in the light
    /// appearance, so the treatment is worth holding: retune an accent, or
    /// deepen a selected pill further, and this is what notices.
    @Test("primary ink stays legible over an accent wash", arguments: accents, grounds)
    func inkIsLegibleOverAnAccentWash(_ accent: ColorToken, _ ground: ColorToken) throws {
        let accentSet = try #require(try ColorSet(at: ColorSet.palette, named: accent.rawValue))
        let groundSet = try #require(try ColorSet(at: ColorSet.palette, named: ground.rawValue))
        let inkSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.inkPrimary.rawValue
        ))

        for appearance in Appearance.allCases {
            for wash in Self.washes {
                let foreground = try #require(inkSet[appearance]?.color)
                let tint = try #require(accentSet[appearance]?.color)
                let ground = try #require(groundSet[appearance]?.color)
                let background = try #require(tint.blended(over: ground, alpha: wash))

                try expectAA(
                    foreground,
                    on: background,
                    "Ink/Primary on \(accent.rawValue) at \(wash)",
                    appearance
                )
            }
        }
    }

    /// The other way to say a goal in its own colour, and the one the catalogue
    /// row takes: `TechniqueListView`'s `rowCaption` sets the goal word in the
    /// accent itself, with the shape facts after it staying `Ink/Tertiary`.
    /// Wherever an accent carries text rather than a stroke, a wash or a badge —
    /// that row, and the coach button in `TechniqueHeader` — it is under WCAG's
    /// 18-point line and answers to AA's 4.5:1. The row is the smaller of the two
    /// and has almost nothing spare: `Accent/Settle` clears the bar at 4.67:1 in
    /// the light appearance, less room than the `Ink/Tertiary` it replaced.
    ///
    /// Against `Surface/Ground` alone, unlike the ink sweep above, and that
    /// exclusion is the finding rather than a shortcut: on `Surface/Raised` three
    /// of the five goal accents land between 4.29:1 and 4.35:1. Both sites are
    /// transparent over `paletteGround()` today — the row through
    /// `listRowBackground(Color.clear)` — so a card introduced behind either is
    /// what takes this treatment out.
    @Test("every goal accent carries the catalogue row's goal word", arguments: goalAccents)
    func goalAccentIsLegibleAsSmallTextOnItsGround(_ accent: ColorToken) throws {
        let accentSet = try #require(try ColorSet(at: ColorSet.palette, named: accent.rawValue))
        let groundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))

        for appearance in Appearance.allCases {
            let foreground = try #require(accentSet[appearance]?.color)
            let background = try #require(groundSet[appearance]?.color)

            try expectAA(
                foreground,
                on: background,
                "\(accent.rawValue) on \(ColorToken.surfaceGround.rawValue)",
                appearance
            )
        }
    }

    /// The session player washes a goal's accent over the ground at
    /// `Theme.Wash.strongest` and reads text on top of it. The wash drags the
    /// ground towards mid-luminance from whichever end it started, so this is
    /// the tightest background in the app and the only ink that survives it is
    /// the primary one — which is why `accentGround(_:)` documents that and why
    /// this measures it.
    ///
    /// Against `Theme.Wash.strongest` rather than a literal, so strengthening
    /// the wash is what fails here: the position line and the nostril hint were
    /// unreadable for as long as the accent behind them was nobody's measured
    /// value.
    @Test("primary ink clears WCAG AA over the strongest accent wash", arguments: accents)
    func primaryInkIsLegibleOverTheAccentGround(_ accent: ColorToken) throws {
        let accentSet = try #require(try ColorSet(at: ColorSet.palette, named: accent.rawValue))
        let groundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))
        let inkSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.inkPrimary.rawValue
        ))

        for appearance in Appearance.allCases {
            let foreground = try #require(inkSet[appearance]?.color)
            let wash = try #require(accentSet[appearance]?.color)
            let ground = try #require(groundSet[appearance]?.color)
            let background = try #require(wash.blended(over: ground, alpha: Theme.Wash.strongest))

            try expectAA(
                foreground,
                on: background,
                "Ink/Primary on \(accent.rawValue) at \(Theme.Wash.strongest)",
                appearance
            )
        }
    }

    /// The session player's seconds-remaining timer — and the hold screen's
    /// counting-up twin — is the one piece of text on that screen the primary
    /// ink does not carry, so it is the one thing there answering to WCAG's 3:1
    /// large-text allowance rather than 4.5:1. It is entitled to that allowance
    /// by size alone: both timers are `.largeTitle`, far past the 18-point line.
    ///
    /// Measured at `Theme.Wash.strongest` like the test above, and pinned here
    /// because the margin is two tenths: retune an accent or strengthen the wash
    /// and the allowance quietly stops covering the one text leaning on it.
    @Test(
        "secondary ink clears the large-text allowance over the accent ground",
        arguments: accents
    )
    func secondaryInkIsLegibleOnTheSessionTimers(_ accent: ColorToken) throws {
        let accentSet = try #require(try ColorSet(at: ColorSet.palette, named: accent.rawValue))
        let groundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))
        let inkSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.inkSecondary.rawValue
        ))

        for appearance in Appearance.allCases {
            let foreground = try #require(inkSet[appearance]?.color)
            let wash = try #require(accentSet[appearance]?.color)
            let ground = try #require(groundSet[appearance]?.color)
            let background = try #require(wash.blended(over: ground, alpha: Theme.Wash.strongest))
            let ratio = try #require(foreground.contrast(against: background))

            #expect(
                ratio >= 3,
                """
                Ink/Secondary on \(accent.rawValue) at \(Theme.Wash.strongest) is \
                \(ratio.formatted(.number.precision(.fractionLength(2)))):1 in \
                \(appearance.rawValue), below the 3:1 the session timers' size buys them
                """
            )
        }
    }

    /// A technique figure strokes its exhale in the goal's accent softened
    /// towards the ground (`OndStyle/FigureShape.swift`). That is a graphical
    /// object rather than text, so the bar is WCAG 1.4.11's 3:1 — and it is the
    /// load-bearing mark on the drawing, the one telling the two halves of a
    /// breath apart.
    ///
    /// Against `Surface/Ground` alone, unlike the ink tests above: every screen
    /// that draws a figure grounds itself with `paletteGround()`, and the list
    /// rows carrying the small ones are transparent over it, so a figure never
    /// sits on a card. There would be nothing spare if one ever did —
    /// `Accent/Settle` softened lands three thousandths under 3:1 on
    /// `Surface/Raised` — which is the reason to come back here and measure the
    /// pair rather than assume this one carries over.
    @Test("every softenable accent survives being softened", arguments: softenable)
    func softenedAccentIsPerceivableOnItsGround(_ accent: ColorToken) throws {
        let accentSet = try #require(try ColorSet(at: ColorSet.palette, named: accent.rawValue))
        let groundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))

        for appearance in Appearance.allCases {
            let ground = try #require(groundSet[appearance]?.color)
            let full = try #require(accentSet[appearance]?.color)
            let softened = try #require(
                full.softened(towards: ground, by: Theme.Softening.strongest)
            )
            let ratio = try #require(softened.contrast(against: ground))

            #expect(
                ratio >= 3,
                """
                \(accent.rawValue) softened by \(Theme.Softening.strongest) is \
                \(ratio.formatted(.number.precision(.fractionLength(2)))):1 in \
                \(appearance.rawValue), below WCAG 1.4.11's 3:1
                """
            )
        }
    }

    /// What the session player's wash can carry that is *not* text, which is a
    /// 3:1 question rather than a 4.5:1 one — and the answer is: those two inks
    /// and nothing else.
    ///
    /// Measured across every accent and every appearance, worst case each:
    ///
    /// | mark | ratio on the strongest wash |
    /// | -- | -- |
    /// | `Ink/Primary` | 7.01:1 |
    /// | `Ink/Secondary` | 3.20:1 |
    /// | an accent at full strength | 2.45:1 |
    /// | an accent softened by `Theme.Softening.strongest` | 1.83:1 |
    /// | `Accent/Still` | 2.04:1 |
    /// | `Ink/Tertiary` | 2.40:1 |
    ///
    /// The four below the line are exactly the four a technique figure is drawn
    /// in (`TechniqueFigure.Ink.colour(on:)` — inhale, exhale, hold, baseline),
    /// so a figure cannot be stroked on `accentGround(_:)` at all. Nor can it be
    /// re-inked onto this ground to get around that: a figure needs four marks
    /// telling each other apart and this ground affords two. A figure on the
    /// player therefore needs `Surface/Ground` restored underneath it, which is
    /// the ground `colour(on:)` is already measured against.
    ///
    /// Only the two that pass are asserted. The failing four are prose because
    /// pinning a number as *too low* would fail the day somebody improves it,
    /// and improving them is not forbidden — it is just not the way out here.
    @Test("the strongest accent wash carries only the two strongest inks", arguments: accents)
    func onlyTheStrongestInksSurviveTheAccentGround(_ accent: ColorToken) throws {
        let accentSet = try #require(try ColorSet(at: ColorSet.palette, named: accent.rawValue))
        let groundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))

        for ink in [ColorToken.inkPrimary, .inkSecondary] {
            let inkSet = try #require(try ColorSet(at: ColorSet.palette, named: ink.rawValue))

            for appearance in Appearance.allCases {
                let foreground = try #require(inkSet[appearance]?.color)
                let wash = try #require(accentSet[appearance]?.color)
                let ground = try #require(groundSet[appearance]?.color)
                let background = try #require(
                    wash.blended(over: ground, alpha: Theme.Wash.strongest)
                )
                let ratio = try #require(foreground.contrast(against: background))

                #expect(
                    ratio >= 3,
                    """
                    \(ink.rawValue) on \(accent.rawValue) at \(Theme.Wash.strongest) is \
                    \(ratio.formatted(.number.precision(.fractionLength(2)))):1 in \
                    \(appearance.rawValue), below WCAG 1.4.11's 3:1 — which leaves the wash \
                    carrying fewer than two marks and nothing on the player able to draw
                    """
                )
            }
        }
    }

    /// AA's 4.5:1 for normal text. Reported with the measured figure, because a
    /// bare "below 4.5" leaves whoever retunes the colour guessing how far.
    private func expectAA(
        _ foreground: CatalogueColor,
        on background: CatalogueColor,
        _ pair: String,
        _ appearance: Appearance
    ) throws {
        let ratio = try #require(foreground.contrast(against: background))

        #expect(
            ratio >= 4.5,
            """
            \(pair) is \(ratio.formatted(.number.precision(.fractionLength(2)))):1 \
            in \(appearance.rawValue), below AA's 4.5:1
            """
        )
    }
}

/// Every ink, and every accent, derived rather than listed: a fourth step of
/// emphasis added to `ColorToken` and then never measured is the same silent gap
/// this file exists to close.
private let inks = ColorToken.allCases.filter { $0.rawValue.hasPrefix("Ink/") }
private let accents = ColorToken.allCases.filter { $0.rawValue.hasPrefix("Accent/") }
/// The accents something can ask for a quieter version of. Derived with two
/// exclusions rather than listed, on the same terms as the line above, so a sixth
/// goal accent is measured the day it is added: `Accent/Still` is drawn on a
/// figure but never softened — a hold is the stillness slate at full strength —
/// and `Accent/Caution` never strokes one. `Accent/Brand` stays in even though no
/// goal wears it, because the marketing site strokes its figures in a softened
/// brand and states the result as a hex nothing else measures.
/// `Accent/Play` joins them: the children's guide draws the flower and the candle
/// at strengths of their own, which `playAccentCarriesTheCandle` measures, and
/// nothing softens it.
private let softenable = accents.filter {
    ![.accentStill, .accentCaution, .accentPlay].contains($0)
}

/// The accents a `TechniqueGoal` can wear. Derived by exclusion for the same
/// reason as the lines above, since `TechniqueGoal.accent` answers in resolved
/// `Color`s and this file measures the catalogue entries behind them by name.
///
/// Off `accents` rather than off `softenable`, whose two exclusions it repeats:
/// that list is about which accents get a quieter version, and the day one of them
/// gains or loses a softened treatment is not a day the set of goal colours
/// changed.
/// `Accent/Play` is out for the reason the diff that added it argues: it is a
/// register's colour, not a goal's, so no catalogue row ever sets a goal word in
/// it and holding it to that row's bar would pin a treatment nothing performs.
private let goalAccents = accents.filter {
    ![.accentStill, .accentCaution, .accentBrand, .accentPlay].contains($0)
}

/// `Surface/Line` is a hairline and never carries text, which is why the grounds
/// are named rather than derived from the prefix.
private let grounds: [ColorToken] = [.surfaceGround, .surfaceRaised]
