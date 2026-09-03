import SwiftUI

/// The visual language. Every colour resolves from `Colors.xcassets`, whose
/// light and dark values are the whole of dark mode — no view branches on
/// `colorScheme`. Each token also carries an Apple Watch idiom entry holding its
/// dark value, because watchOS resolves the Any slot; a colour is not done until
/// it has all three. Mapping a domain value onto an accent is `OndStyle`'s job.
public enum Theme {
    /// A five-step scale. Constraining spacing to five values is what keeps a
    /// minimal interface looking deliberate rather than merely sparse.
    public enum Spacing {
        public static let tight: CGFloat = 4
        public static let close: CGFloat = 8
        public static let standard: CGFloat = 16
        /// The page margin — what every screen's content keeps from the
        /// display's edge. Off the 4-point rhythm because it is the refresh
        /// spec's own number, not a spacing step.
        public static let page: CGFloat = 20
        public static let loose: CGFloat = 24
        /// The gap between two blocks that ask different questions — the
        /// summary's record and its mood check. `loose` separates lines
        /// inside one block, so it cannot also say where a block ends.
        public static let section: CGFloat = 40
    }

    /// Fixed sizes — what a control has to hit, and what a face is set at —
    /// as opposed to space a view may take.
    public enum Metrics {
        /// The space a large system button puts around its own label. System
        /// styles size themselves as label plus their control-size inset, so
        /// pinning the label alone leaves a custom capsule shorter than a
        /// system button beside it; anything drawing its own capsule adds this.
        public static let primaryActionInset: CGFloat = 14

        /// The Human Interface Guidelines' minimum touch target. Most controls
        /// take it through `tapTarget()`; named here because the shapes that
        /// modifier cannot express — a square icon button, the blank keeping a
        /// column aligned with one — still have to land on the same number.
        public static let minimumTapTarget: CGFloat = 44

        /// How tall the one action a screen is built around stands — Home's
        /// Breathe capsule. The spec's number: taller than the large control
        /// size, so that against the 44-point line under it the sizes say
        /// which is the action without a second colour.
        public static let leadActionHeight: CGFloat = 60

        /// The one size the wrist sets its display face at. 26 rather than
        /// the refresh spec's 22, to compensate the text cut's x-height as
        /// `Typeface` describes.
        public static let wristDisplaySize: CGFloat = 26
    }

    /// How often a drawing is redrawn, where the answer is not "as often as the
    /// display can".
    public enum Motion {
        /// The tick a drawing gets when nobody is following it closely: thirty
        /// a second, not the display's 120 — the extra redraws keep the
        /// pipeline awake and buy a resting figure nothing. The session guide
        /// is deliberately *un*capped otherwise: that one is being followed
        /// breath for breath.
        public static let restfulFrameInterval = 1.0 / 30
    }

    /// Corner radii. Its own scale rather than a reach into `Spacing`: a radius
    /// that borrows a gap's value is tied to it by coincidence, and retuning the
    /// space between two labels would reshape every card on the way past.
    public enum Radius {
        /// The refresh spec's shared chrome puts cards at 22–28pt; this is the
        /// low end of that band, and the hero surfaces that want the top of it
        /// (Home's sheet, the Lock Screen) state their own wider value.
        public static let card: CGFloat = 22

        /// The rounded end of a data mark — a bar's top, and nothing else.
        ///
        /// Far tighter than a card's, and deliberately: a bar is read against
        /// its neighbours, and a radius that softened it as much as a card would
        /// round away the difference between two adjacent days.
        public static let mark: CGFloat = 4
    }

    /// What lifts a card off the ground — load-bearing: `Surface.raised` is
    /// 1.14:1 against the light ground, so an unshadowed card has no edge. A
    /// fixed near-black, not `Ink.primary`, which inverts. Poured on the fill
    /// rather than `View.shadow`, which falls from the card's title too. The
    /// radius is half the spec's CSS blur — CSS spans two deviations, SwiftUI one.
    public enum Shadow {
        /// Every card, including the shared `glassCard()` recipe. The spec's
        /// deeper hero shadow left with the surface that wore it; it comes
        /// back the day a screen leads with a card again.
        public static let list: ShadowStyle = .drop(color: ink.opacity(0.05), radius: 12, y: 6)

        /// `Ink.primary`'s light value, frozen. See the note above on why this
        /// cannot be the adaptive token.
        private static let ink = Color(red: 11 / 255, green: 18 / 255, blue: 20 / 255)
    }

    /// How an accent is poured into glass. Its own scale rather than the
    /// opaque cards' opacities: glass carries luminance of its own, so
    /// `Fill.selection` disappears into it entirely. These are the strengths
    /// that survive the material.
    public enum Glass {
        /// A selected surface's accent. Roughly two and a half times the
        /// opaque card's tint, which is what it takes to be as legible.
        public static let selection: Double = 0.45
    }

    /// How strongly an opaque fill carries an accent while the text on it
    /// stays an ink — the opaque counterpart to `Glass.selection`.
    /// `ThemeColorTests` measures primary ink over this value, so retuning it
    /// is a legibility decision. A selected `FilterPill` shares it, ringing
    /// itself at stroke strength rather than deepening the fill.
    public enum Fill {
        public static let selection: Double = 0.18
    }

    /// How strongly an accent is poured over `Surface.ground` when a whole
    /// screen wears a technique's colour. At `strongest` only `Ink.primary`
    /// still clears AA (8.60:1 at worst; secondary 4.18:1, tertiary 3.55:1).
    /// A named ceiling because raising it is a legibility decision —
    /// `ThemeColorTests` fails when it stops holding.
    public enum Wash {
        /// The top of the gradient, and the only value the guarantee is
        /// measured at — text can sit anywhere under it.
        public static let strongest: Double = 0.35
        /// The bottom of it, where the accent is barely present and the ground
        /// is almost the palette's own.
        public static let faintest: Double = 0.05

        /// How far past a drawing the wash is held off, as a multiple of the
        /// drawing's own extent — see `figureGround()`. The excess is all fade;
        /// the opaque part must reach the circle inscribed in the drawing's
        /// frame, or a stroke lands back on a half-faded wash. Half again puts
        /// the fade's end at a phone screen's edge behind a 260-point figure.
        public static let clearance: CGFloat = 1.5
    }

    /// How far an accent is pulled towards the ground to hush a line — the
    /// exhale stroke — so the bar is WCAG 1.4.11's 3:1, not the inks' 4.5:1. One
    /// fraction for both appearances: dark tolerates 0.42 where light gives out
    /// at 0.24, and splitting the overlapping ranges would break the invariant
    /// that no code branches on `colorScheme`. `ThemeColorTests` holds the ceiling.
    public enum Softening {
        /// The most an accent gives up while still reading against the ground.
        /// `Accent/Restore` runs out first: about 3.27:1 over the light ground
        /// at 0.20. `Accent/Brand` is not in the guarantee — its light value is
        /// pinned to the icon ring and softens through 3:1 before 0.20, so no
        /// app figure may stroke a softened Brand (the site has its own floor).
        public static let strongest: Double = 0.20
    }

    /// The grounds content sits on. A screen that draws its own background — the
    /// session player, which covers the system's — picks from here rather than
    /// leaving whatever the presentation happened to put behind it.
    public enum Surface {
        /// The base of the app: a cool near-white, or the deep blue-graphite
        /// the wordmark sits on.
        public static let ground = ColorToken.surfaceGround.color
        /// One step off the ground, for anything meant to read as a card.
        public static let raised = ColorToken.surfaceRaised.color
        /// A second lift, for a surface that has to read as raised while
        /// sitting on `raised` — a chip on a card, a selected row in a sheet.
        public static let raisedAlt = ColorToken.surfaceRaisedAlt.color
        /// The corner a ground is lit from: the far end of a ground's radial,
        /// where `ground` is the near end — see `RadialGradient.groundGlow`.
        /// A token because it needs both appearances, lifted toward light in
        /// each so the glow reads the same way rather than inverting.
        public static let lit = ColorToken.surfaceLit.color
        /// Hairlines — a stroke or a divider, never a fill. Carries alpha
        /// rather than a flattened value so the same hairline reads correctly
        /// over all three surfaces.
        public static let line = ColorToken.surfaceLine.color
    }

    /// Text, in three steps of emphasis. The quieter two carry their fade as
    /// alpha, so one token reads the same over all three surfaces. All three
    /// clear AA (4.5:1) against every `Surface` ground in both appearances —
    /// `ThemeColorTests` measures it — and every ink is set at caption sizes, so
    /// no 3:1 allowance applies; fading one with `.opacity` is nobody's measured value.
    public enum Ink {
        /// Body and headings.
        public static let primary = ColorToken.inkPrimary.color
        /// Supporting copy: a summary under a title, a caption under a number.
        public static let secondary = ColorToken.inkSecondary.color
        /// Present but receding — a disclaimer, a hint someone has already read.
        ///
        /// As faint as AA allows and no fainter: 4.75:1 at its worst in both
        /// appearances (over `raisedAlt` dark, over `ground` light), so a step
        /// further back is not available.
        public static let tertiary = ColorToken.inkTertiary.color
    }

    /// Colours owned by controls rather than by the content around them.
    public enum Action {
        /// The label over a full-strength brand action. White over the deeper
        /// light-appearance brand, deep ink over the brighter dark one — a
        /// single foreground misses AA at one end or the other.
        public static let brandLabel = ColorToken.actionBrandLabel.color
    }

    /// Accents, named for the feeling rather than the colour, so a palette
    /// change is a one-line edit here. The five goal accents walk one arc of
    /// the wheel with amber opposite: one palette, told apart at badge size.
    public enum Accent {
        /// The app icon's blue — the app's own colour, for anything no
        /// technique owns. Holds `Breath.inhale`'s values on purpose: the icon
        /// is the breathing shape at rest. Its own token so the pairs can move
        /// independently — it matches `settle` only in the dark appearance.
        public static let brand = ColorToken.accentBrand.color
        /// `brand` deepened to read as text on a light surround. Exists because
        /// `brand`'s light value is pinned to the icon ring at 4.01:1 against
        /// `Surface.ground` — under the 4.5:1 floor, which is why
        /// `ThemeColorTests` excludes it from the goal word's sweep. Small type
        /// in the app's own blue wants this; as a fill, `brand` is the token.
        public static let brandText = ColorToken.accentBrandText.color
        /// Cool sea blue — settling.
        public static let settle = ColorToken.accentSettle.color
        /// Slate indigo — night. Deliberately deeper than `Breath.hold`: a
        /// sleep session draws holds too, and the two must separate inside one
        /// frame.
        public static let night = ColorToken.accentNight.color
        /// `night` lifted far enough to read as text on a dark surround — a
        /// suggestion card's eyebrow, never a fill. As a fill, `night` is the
        /// token.
        public static let nightText = ColorToken.accentNightText.color
        /// Warm amber — activating.
        public static let spark = ColorToken.accentSpark.color
        /// Muted green — recovery.
        public static let restore = ColorToken.accentRestore.color
        /// Sea teal — attention held on something.
        public static let attend = ColorToken.accentAttend.color
        /// Rust — a caution worth reading. Kept well round the wheel from
        /// `spark` so the energising accent never reads as a warning.
        public static let caution = ColorToken.accentCaution.color
        /// Warm rose — the register a small child is spoken to in. The one
        /// accent a route rather than a goal reaches for, so it gets its own
        /// token: an alias of `spark` would make retuning the energising accent
        /// silently retune the children's screen.
        public static let play = ColorToken.accentPlay.color
    }

    /// The breath's own colours. Phase colour and goal colour answer to
    /// different axes and must never trade places: a goal accent colours the
    /// surround, and the breath core stays the phase colour everywhere.
    /// `inhale` and `hold` share lightness and chroma, 65° apart in hue —
    /// equals rather than a hierarchy.
    public enum Breath {
        /// The inhale, and the core of the breathing shape on every surface.
        /// Holds `Accent.brand`'s values on purpose — the icon is this shape
        /// at rest.
        public static let inhale = ColorToken.breathInhale.color
        /// Holds, everywhere they appear: a rhythm bar's hold segment, the
        /// marketing figure's hold stroke, and the gradients. No surface draws
        /// a hold ring.
        public static let hold = ColorToken.breathHold.color
        /// Vapour — drawn at low opacities, and never the only carrier of
        /// state. The dark value fades the inhale; the light one is its own
        /// designed hue, because the dark value at any alpha washes out on
        /// the light ground.
        public static let exhale = ColorToken.breathExhale.color
    }
}
