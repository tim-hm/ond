import Foundation
@testable import OndUI
import Testing

/// Breath marks must meet 3:1 contrast against the figure ground.
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
