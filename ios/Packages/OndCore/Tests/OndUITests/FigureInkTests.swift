import Foundation
@testable import OndUI
import Testing

/// The colours that carry a drawing rather than a word, measured at the strength
/// they are actually drawn.
///
/// Apart from `ThemeColorTests` because they are the exceptions to it: both are
/// excluded from that file's derived sweeps — `Breath/Hold` by its prefix, since
/// no goal wears a phase colour, and `Accent/Play` is never worn by a goal — and
/// a colour excluded from every sweep is a colour resting on nothing at all,
/// which is how the hold stroke went unmeasured for as long as it did. A figure
/// also answers to a different bar than text: WCAG 1.4.11's 3:1 for a graphic
/// that carries meaning, not AA's 4.5:1.
///
/// Against `Surface/Ground` throughout, because every drawing here sits on the
/// ground `figureGround()` restores rather than on the accent wash.
@Suite("The accents that carry a figure")
struct FigureInkTests {
    /// A hold is `Breath/Hold` at full strength, on every surface that marks
    /// one — the figure's hold stroke, the session guide's held tint. It has
    /// the least room of the figure's marks in the light appearance, 4.47:1,
    /// and the breath figure makes it half the phases.
    @Test("the hold's indigo carries a hold stroke at full strength")
    func holdInkIsPerceivableOnItsGround() throws {
        try expectPerceivable(.breathHold, at: 1, "the hold stroke")
    }

    /// The playful register draws its whole guide in one accent: the flower and
    /// the candle are `Accent/Play` fills with no ink and no second mark to lean
    /// on, and no words a child that age can read either.
    ///
    /// **At the strengths actually drawn**, which is what the first version of
    /// this got wrong — it measured the token at full opacity and passed at
    /// 5.51:1 while the wax it claimed to cover was drawn at 0.42 and sat at
    /// 1.88:1. The wax is the entire picture once the flame is out, which is
    /// where every exhale ends.
    ///
    /// The glow is deliberately absent: it is light rather than a mark, with the
    /// standing the session ring's 0.18 track has, and carries nothing that is
    /// lost when it goes unseen.
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
