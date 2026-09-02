import Foundation
@testable import OndUI
import Testing

/// Every contrast this palette has to hold, measured from the catalogue rather than
/// judged by eye. Whether the catalogue behind it is well-formed at all — every
/// token naming a colourset, every colourset drawn twice — is
/// `PaletteIntegrityTests`. Every ratio is computed from the catalogue on disk
/// rather than a resolved `Color`, for the reason `ColorSet` documents.
@Suite("Theme colours")
struct ThemeColorTests {
    /// Every ink is drawn on one of the three grounds and every ground carries
    /// caption-size copy somewhere, so the bar is AA's 4.5:1 throughout — no
    /// large-text allowance. The quiet inks are flattened over the measured ground:
    /// the colour a person sees, not the stored base. From the catalogue, not by eye —
    /// `Ink/Tertiary` shipped at 2.72:1 in light and looked like a design choice.
    @Test(
        "every ink clears WCAG AA on every ground, on every surface",
        arguments: inks,
        grounds
    )
    func inkIsLegibleOnEveryGround(_ ink: ColorToken, _ ground: ColorToken) throws {
        let inkSet = try #require(try ColorSet(at: ColorSet.palette, named: ink.rawValue))
        let groundSet = try #require(try ColorSet(at: ColorSet.palette, named: ground.rawValue))

        for appearance in Appearance.allCases {
            let background = try #require(groundSet[appearance]?.color)
            let foreground = try #require(inkSet[appearance]?.color.flattened(over: background))

            try expectAA(
                foreground,
                on: background,
                "\(ink.rawValue) on \(ground.rawValue)",
                appearance
            )
        }
    }

    /// A prominent glass button keeps the brand at full strength, whose light
    /// and dark variants sit on opposite sides of the luminance range. The
    /// label therefore adapts in the other direction instead of relying on the
    /// system's white prominent label, which fails over the brighter dark blue.
    @Test("the brand action label clears WCAG AA in both appearances")
    func brandActionLabelIsLegible() throws {
        let foregroundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.actionBrandLabel.rawValue
        ))
        let backgroundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.accentBrand.rawValue
        ))

        for appearance in Appearance.allCases {
            let foreground = try #require(foregroundSet[appearance]?.color)
            let background = try #require(backgroundSet[appearance]?.color)

            try expectAA(
                foreground,
                on: background,
                "Action/BrandLabel on Accent/Brand",
                appearance
            )
        }
    }

    /// The coach's send button is a two-tone glyph: the ground's colour as the
    /// arrow, `Breath/Inhale` as the circle under it. A glyph is a graphical
    /// object, so the bar is WCAG 1.4.11's 3:1 rather than AA's 4.5:1. Measured
    /// here because the pair is the other way round from every sweep in this
    /// file: the ground is the mark, and the breath colour is behind it.
    @Test("the coach's send arrow reads against its own circle")
    func sendArrowIsLegibleOnItsCircle() throws {
        let arrowSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))
        let circleSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.breathInhale.rawValue
        ))

        for appearance in Appearance.allCases {
            let background = try #require(circleSet[appearance]?.color)
            let foreground = try #require(arrowSet[appearance]?.color)
            let ratio = try #require(foreground.contrast(against: background))

            #expect(
                ratio >= 3,
                """
                Surface/Ground on Breath/Inhale is \
                \(ratio.formatted(.number.precision(.fractionLength(2)))):1 in \
                \(appearance.rawValue), below WCAG 1.4.11's 3:1 — which leaves the \
                coach's send button an arrow nobody can pick out of its circle
                """
            )
        }
    }

    /// Where a breath colour carries words rather than a mark — the Dynamic
    /// Island's phase count, in `Breath/Exhale` at caption size — the bar is
    /// AA, not the 3:1 `FigureInkTests` holds the same three to. Dark only:
    /// the Island is black whatever the phone wears, and every breath colour
    /// misses AA on the light ground, which is what keeps them off it.
    @Test("a breath colour carrying words clears WCAG AA", arguments: breaths)
    func breathColourIsLegibleAsSmallText(_ breath: ColorToken) throws {
        let breathSet = try #require(try ColorSet(at: ColorSet.palette, named: breath.rawValue))
        let groundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))

        let background = try #require(groundSet[.dark]?.color)
        let foreground = try #require(breathSet[.dark]?.color)

        try expectAA(foreground, on: background, "\(breath.rawValue) on Surface/Ground", .dark)
    }

    /// The strengths an accent wash carries a word at. 0.15 is `GoalBadge`;
    /// `Theme.Fill.selection` is an opaque control drawn as chosen — a
    /// schedule's weekday, the coach's selected reply, and a selected
    /// `FilterPill`, which washes and rings its surface rather than moving the
    /// word into the accent.
    private static let washes = [0.15, Theme.Fill.selection]

    /// A badge sets a word in primary ink over a wash of an accent — `GoalBadge`
    /// names a technique's goal, `FilterPill` is the one you can press. Drawn the
    /// obvious way, accent carrying the text, four of five goal accents miss AA
    /// in light — so the treatment is worth holding: retune an accent or deepen a
    /// selected pill further, and this is what notices.
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
                let tint = try #require(accentSet[appearance]?.color)
                let ground = try #require(groundSet[appearance]?.color)
                let background = try #require(tint.blended(over: ground, alpha: wash))
                let foreground = try #require(
                    inkSet[appearance]?.color.flattened(over: background)
                )

                try expectAA(
                    foreground,
                    on: background,
                    "Ink/Primary on \(accent.rawValue) at \(wash)",
                    appearance
                )
            }
        }
    }

    /// The other way to say a goal in its own colour: `rowCaption` sets the goal word
    /// in the accent, and wherever an accent carries text on the ground itself (that
    /// row, the coach button) the bar is AA's 4.5:1. That floor is why the light accents
    /// sit deeper than the refresh spec's L−0.14 rule — at spec values the row missed
    /// AA. Against `Surface/Ground` alone: nothing draws the raised pair.
    @Test("every text accent carries the catalogue row's goal word", arguments: textAccents)
    func textAccentIsLegibleAsSmallTextOnItsGround(_ accent: ColorToken) throws {
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
    /// `Theme.Wash.strongest` and reads text on it — the tightest background in the
    /// app; only the primary ink survives, which `accentGround(_:)` documents. Against
    /// the constant rather than a literal, so strengthening the wash fails here: the
    /// position line was unreadable while the accent was nobody's measured value.
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
            let wash = try #require(accentSet[appearance]?.color)
            let ground = try #require(groundSet[appearance]?.color)
            let background = try #require(wash.blended(over: ground, alpha: Theme.Wash.strongest))
            let foreground = try #require(inkSet[appearance]?.color.flattened(over: background))

            try expectAA(
                foreground,
                on: background,
                "Ink/Primary on \(accent.rawValue) at \(Theme.Wash.strongest)",
                appearance
            )
        }
    }

    /// The seconds-remaining timer — and the hold screen's counting-up twin — is the
    /// one text on that screen the primary ink does not carry, so the one thing
    /// answering to WCAG's 3:1 large-text allowance; both are `.largeTitle`, far past
    /// the 18-point line. Measured at `Theme.Wash.strongest`, pinned because the margin
    /// is two tenths: strengthen the wash and the allowance quietly stops covering it.
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
            let wash = try #require(accentSet[appearance]?.color)
            let ground = try #require(groundSet[appearance]?.color)
            let background = try #require(wash.blended(over: ground, alpha: Theme.Wash.strongest))
            let foreground = try #require(inkSet[appearance]?.color.flattened(over: background))
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

    /// A technique figure strokes its exhale in the goal's accent softened towards the
    /// ground — a graphic, so the bar is 1.4.11's 3:1, and it is the mark telling a
    /// breath's halves apart. Against `Surface/Ground` alone: every figure screen
    /// grounds with `paletteGround()`, so a figure never sits on a card — and nothing
    /// is spare if one did: `Accent/Settle` softened misses 3:1 on `Surface/Raised`.
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

    /// What the wash can carry that is *not* text — a 3:1 question. The inks pass
    /// (worst `Ink/Tertiary`, 3.55:1); a full accent, `Breath/Hold` and a softened
    /// accent fall below — three of a figure's four marks, so a figure on the player
    /// needs `Surface/Ground` restored underneath. Only the two the player reads are
    /// asserted: pinning a failing number as *too low* would fail when it improves.
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
                let wash = try #require(accentSet[appearance]?.color)
                let ground = try #require(groundSet[appearance]?.color)
                let background = try #require(
                    wash.blended(over: ground, alpha: Theme.Wash.strongest)
                )
                let foreground = try #require(
                    inkSet[appearance]?.color.flattened(over: background)
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
/// The accents something can ask for a quieter version of, derived with three
/// exclusions so a sixth goal accent is measured the day it lands. `Accent/Caution`
/// never strokes a figure; `Accent/Play` is drawn at strengths of its own and never
/// softened; `Accent/Brand` softened lands under 3:1 on the light ground, so only
/// the site softens it — by a shallower fraction `SitePaletteTests` holds.
private let softenable = accents.filter {
    ![.accentCaution, .accentPlay, .accentBrand].contains($0)
}

/// Every accent a surface sets small words in: the five goals, the lifted twins
/// `sleep` and the brand keep, and the playful register's own. Derived by
/// exclusion, so a new one is measured the day it lands — `Accent/Caution` and
/// `Accent/Brand` are the two that never carry body copy. `Accent/Play` is here
/// because `CopyRegister.textAccent(over:)` answers with it and keeps no twin.
private let textAccents = accents.filter {
    ![.accentCaution, .accentBrand].contains($0)
}

/// `Surface/Line` is a hairline and never carries text, which is why the grounds
/// are named rather than derived from the prefix.
private let grounds: [ColorToken] = [
    .surfaceGround,
    .surfaceRaised,
    .surfaceRaisedAlt,
    .surfaceLit,
]
