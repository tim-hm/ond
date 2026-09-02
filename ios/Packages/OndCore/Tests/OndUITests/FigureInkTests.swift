import Foundation
@testable import OndUI
import Testing

/// The colours that carry a drawing rather than a word, measured at the strength
/// they are drawn. Apart from `ThemeColorTests` because both are excluded from its
/// derived sweeps — a colour in no sweep rests on nothing, which is how the hold
/// stroke went unmeasured. A graphic answers to 1.4.11's 3:1, not AA's 4.5:1;
/// against `Surface/Ground` throughout, the ground `figureGround()` restores.
@Suite("The accents that carry a figure")
struct FigureInkTests {
    /// Every phase of a breath at full strength: the figure's strokes, the
    /// session guide's tints, the chart's bars. Derived from the prefix, so a
    /// fourth phase colour is measured the day it lands. None of the three
    /// clears AA on this ground — 4.06, 4.47 and 3.39 in light — which is why
    /// `Accent/BrandText` carries the small type beside `Breath/Inhale`.
    @Test("every breath colour carries a mark at full strength", arguments: breaths)
    func breathInkIsPerceivableOnItsGround(_ breath: ColorToken) throws {
        try expectPerceivable(breath, at: 1, "the \(breath.rawValue) mark")
    }

    /// The playful register draws its whole guide in one accent: flower and candle are
    /// `Accent/Play` fills with no ink, no second mark, and no words a child that age
    /// can read. **At the strengths actually drawn** — measuring the token at full
    /// opacity passed 5.51:1 while the wax was drawn at 0.42 and sat at 1.88:1, and
    /// the wax is the whole picture once the flame is out. The glow is light, no mark.
    @Test(
        "the playful guide's marks are perceivable at the strength they are drawn",
        arguments: [("the wax", 0.78), ("the wick", 0.9), ("the flame's tip", 0.72)]
    )
    func playAccentCarriesTheCandle(_ mark: (name: String, alpha: Double)) throws {
        try expectPerceivable(.accentPlay, at: mark.alpha, mark.name)
    }

    /// WCAG 1.4.11's 3:1, measured on `token` blended over the ground at the
    /// opacity the drawing uses. Reported with the figure, because a bare "below
    /// 3" leaves whoever retunes the colour guessing how far.
    private func expectPerceivable(
        _ token: ColorToken,
        at alpha: Double,
        _ mark: String
    ) throws {
        let accentSet = try #require(try ColorSet(at: ColorSet.palette, named: token.rawValue))
        let groundSet = try #require(try ColorSet(
            at: ColorSet.palette,
            named: ColorToken.surfaceGround.rawValue
        ))

        for appearance in Appearance.allCases {
            let ground = try #require(groundSet[appearance]?.color)
            let accent = try #require(accentSet[appearance]?.color)
            let drawn = try #require(accent.blended(over: ground, alpha: alpha))
            let ratio = try #require(drawn.contrast(against: ground))

            #expect(
                ratio >= 3,
                """
                \(mark) is \(token.rawValue) at \(alpha), measuring \
                \(ratio.formatted(.number.precision(.fractionLength(2)))):1 in \
                \(appearance.rawValue), below WCAG 1.4.11's 3:1
                """
            )
        }
    }
}

/// The three phases of a breath, derived rather than listed, the way
/// `ThemeColorTests` derives its inks and accents. Shared with that file,
/// which holds the same three to AA where they carry words.
let breaths = ColorToken.allCases.filter { $0.rawValue.hasPrefix("Breath/") }
