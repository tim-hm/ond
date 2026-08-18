import SwiftUI

/// The visual language, in one place.
///
/// Every colour resolves from `Colors.xcassets` in this target, where each token
/// carries a light and a dark value. That is the whole of the app's dark mode:
/// the system picks a variant per appearance, so no view branches on
/// `colorScheme` and no screen can be themed for only one of them.
///
/// Each token also carries an Apple Watch idiom entry holding its dark value,
/// because watchOS resolves the Any slot rather than an appearance — without it
/// the wrist renders light-mode ink on an always-black screen. A new colour is
/// not done until it has all three values.
///
/// The palette is the marketing site's (`web/style.css`) — cold air, not warm
/// bath: breath blues over a deep blue-graphite, or over a cool near-white — so
/// the app and the page a person arrives from are recognisably the same
/// product.
///
/// Deliberately holds no domain types — this package knows nothing about
/// techniques or goals, which is what keeps the dependency pointing one way
/// (docs/code-structure.md). Mapping a domain value onto an accent is
/// `OndStyle`'s job: it depends on this module and on `OndKit`, so both
/// apps read one mapping without this one learning anything.
public enum Theme {
    /// A four-step scale. Constraining spacing to four values is what keeps a
    /// minimal interface looking deliberate rather than merely sparse.
    public enum Spacing {
        public static let tight: CGFloat = 4
        public static let close: CGFloat = 8
        public static let standard: CGFloat = 16
        public static let loose: CGFloat = 24
    }

    /// Sizes a control has to hit, as opposed to space it may take.
    public enum Metrics {
        /// The space a large system button puts around its own label, which a
        /// hand-drawn one has to reproduce to stand the same height.
        ///
        /// The system styles size themselves as label plus their control-size
        /// inset, so pinning the label alone leaves a custom capsule shorter
        /// than a `.borderedProminent` beside it. This is that inset at
        /// `.controlSize(.large)` — the size every concluding action is set in
        /// — and only `CapsuleActionStyle` should need it.
        public static let primaryActionInset: CGFloat = 14

        /// The Human Interface Guidelines' minimum touch target. A control
        /// smaller than this is one somebody has to aim at.
        ///
        /// Most controls take it through `tapTarget()`, which is the only way
        /// that also makes the grown frame tappable. It is named here rather
        /// than inside that modifier because the shapes it cannot express —
        /// a square icon button, and the blank that has to keep a column
        /// aligned with one — still have to land on the same number.
        public static let minimumTapTarget: CGFloat = 44
    }

    /// How often a drawing is redrawn, where the answer is not "as often as the
    /// display can".
    public enum Motion {
        /// The tick a drawing gets when nobody is following it closely.
        ///
        /// Thirty a second rather than the display's own rate, which on a
        /// ProMotion screen is 120. Four times the redraws keep the display
        /// pipeline awake four times as often and buy nothing a resting figure —
        /// a three-second cosine, or an arc filling over a whole phase — can
        /// show at that rate.
        ///
        /// Named because four drawings want it and they are in three different
        /// features: the onboarding orb, the coach's thinking dot, and both
        /// session guides once Reduce Motion has swapped the scaling body for a
        /// filling arc. The session guide is deliberately *un*capped otherwise:
        /// that one is being followed breath for breath.
        public static let restfulFrameInterval = 1.0 / 30
    }

    /// Corner radii. Its own scale rather than a reach into `Spacing`: a radius
    /// that borrows a gap's value is tied to it by coincidence, and retuning the
    /// space between two labels would reshape every card on the way past.
    public enum Radius {
        /// The refresh spec's shared chrome puts cards at 22–28pt; this is the
        /// low end of that band, and the hero surfaces that want the top of it
        /// (the continue card, the Lock Screen) state their own wider value.
        public static let card: CGFloat = 22

        /// The rounded end of a data mark — a bar's top, and nothing else.
        ///
        /// Far tighter than a card's, and deliberately: a bar is read against
        /// its neighbours, and a radius that softened it as much as a card would
        /// round away the difference between two adjacent days.
        public static let mark: CGFloat = 4
    }

    /// How an accent is poured into glass.
    ///
    /// Its own scale rather than a reach into the opacities the opaque cards
    /// use: glass already carries luminance of its own, so the `Fill.selection`
    /// that reads as a selected fill on an opaque surface disappears into it
    /// entirely. These are the strengths that survive the material.
    public enum Glass {
        /// A selected surface's accent. Roughly two and a half times the
        /// opaque card's tint, which is what it takes to be as legible.
        public static let selection: Double = 0.45
    }

    /// How strongly an opaque fill carries an accent while the text on it
    /// stays an ink — a schedule's chosen weekday, the person's side of the
    /// coach chat.
    ///
    /// The opaque counterpart to `Glass.selection`, and a named strength for
    /// the same reason: two screens marking "this one is the accent's" at
    /// strengths of their own stop reading as one state, and `ThemeColorTests`
    /// measures primary ink over this value, so retuning it is a legibility
    /// decision. A selected `FilterPill` shares it too, and rings itself in the
    /// same accent at stroke strength rather than deepening the fill — the
    /// refresh's treatment, and the reason the 0.30 wash that used to be
    /// measured here is measured nowhere now.
    public enum Fill {
        public static let selection: Double = 0.18
    }

    /// How strongly an accent is poured over `Surface.ground` when a whole
    /// screen wears a technique's colour.
    ///
    /// Its own scale rather than `Glass`'s: glass carries luminance of its own
    /// and these values go straight onto the ground, where they move it far
    /// enough to decide what can be read on top. At `strongest` the ground
    /// lands mid-luminance whichever accent it carries — `Ink.secondary`
    /// measures 4.18:1 at its worst (the spark wash, dark) and `Ink.tertiary`
    /// 3.55:1, both below AA, while `Ink.primary` holds 8.60:1 at its worst.
    /// That is the whole reason this
    /// is a named ceiling instead of a literal beside a gradient: raising it is
    /// a legibility decision, and `ThemeColorTests` fails when it stops holding.
    public enum Wash {
        /// The top of the gradient, and the only value the guarantee is
        /// measured at — text can sit anywhere under it.
        public static let strongest: Double = 0.35
        /// The bottom of it, where the accent is barely present and the ground
        /// is almost the palette's own.
        public static let faintest: Double = 0.05

        /// How far past a drawing the wash is held off, as a multiple of the
        /// drawing's own extent — see `figureGround()`.
        ///
        /// The whole of the excess is fade. What is *not* negotiable is the
        /// opaque part: it has to reach the circle inscribed in the drawing's
        /// frame, because that is as far out as a drawing keeping inside its own
        /// bounds can put a stroke, and a stroke on a half-faded patch is a
        /// stroke back on a partial wash. So this number only ever decides how
        /// gently the ground dissolves, never how much of it there is.
        ///
        /// A half again puts the last of the fade at the edge of a phone screen
        /// behind a 260-point figure, which is as soft as the room allows — and
        /// is why the player keeps its wash as bands above and below the drawing
        /// rather than all the way in to it.
        public static let clearance: CGFloat = 1.5
    }

    /// How far an accent is pulled towards the ground when a drawing needs a
    /// quieter version of the same colour.
    ///
    /// The mirror of `Wash`: that one pours an accent over the ground to tint
    /// it, this one pulls an accent towards the ground to hush it. What is
    /// softened this way is a line rather than text — the exhale stroke on a
    /// technique figure — so the bar is WCAG 1.4.11's 3:1 for a graphical object
    /// that carries meaning, not the 4.5:1 the inks answer to.
    ///
    /// One fraction for both appearances, which is the part worth reading before
    /// changing it. White has far less room than the near-black does: over the
    /// dark ground every accent stays legible softened as far as 0.42, and over
    /// white the tightest of them gives out at 0.24. But the two ranges overlap,
    /// so one number under the tighter ceiling serves both grounds, and splitting
    /// it in two would buy a little more separation in the dark appearance at the
    /// price of the invariant this palette is built on — that the asset catalogue
    /// is the whole of dark mode and no code branches on `colorScheme`.
    ///
    /// A named ceiling for the same reason `Wash.strongest` is one: raising it is
    /// a legibility decision, and `ThemeColorTests` fails when it stops holding.
    public enum Softening {
        /// The most an accent gives up while still reading as itself against the
        /// ground.
        ///
        /// `Accent/Restore` is the goal accent that runs out first: at 0.20 it
        /// measures about 3.27:1 over the light ground, which is the margin a
        /// 1.6-point stroke wants before the next palette nudge spends it.
        /// `Accent/Brand` is not in this guarantee at all — its light value is
        /// pinned to the icon ring and softens through 3:1 before 0.20, so no
        /// app figure may stroke a softened Brand; the site, the one consumer
        /// that wants one, takes a shallower fraction with its own floor in
        /// `SitePaletteTests`.
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
        /// Hairlines — a stroke or a divider, never a fill. Carries alpha
        /// rather than a flattened value so the same hairline reads correctly
        /// over all three surfaces.
        public static let line = ColorToken.surfaceLine.color
    }

    /// Text, in three steps of emphasis. The quieter two carry their fade as
    /// alpha in the catalogue rather than as flattened values, so one token
    /// reads the same over all three surfaces instead of being measured for
    /// only one of them.
    ///
    /// As drawn, all three clear WCAG AA for normal text — 4.5:1 — against
    /// every `Surface` ground in both appearances, which `ThemeColorTests`
    /// measures rather than takes on trust. Every ink is used at `.caption` or
    /// `.footnote` somewhere, so none of them qualifies for the 3:1 large-text
    /// allowance, and the scale has less room at the quiet end than it looks
    /// like it should. Fading one further with `.opacity` spends that margin
    /// and is nobody's measured value.
    ///
    /// The alphas sit above the refresh spec's on purpose — the spec's
    /// tertiary would ship at 2.97:1 light and 3.65:1 dark, and the floor wins
    /// here: 0.60/0.52 is as recessive as AA allows over `raisedAlt`, the
    /// tightest ground.
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

    /// Accents, named for the feeling rather than the colour, so a palette
    /// change is a one-line edit here instead of a search across views.
    ///
    /// The five goal accents walk one arc of the wheel, green through teal and
    /// blue to indigo, with amber opposite: related enough to look like one
    /// palette, separated enough to tell apart at badge size.
    public enum Accent {
        /// The app icon's blue — the app's own colour, for anything no technique
        /// owns. Every button in both apps wears it, by way of the app-level
        /// tint, along with onboarding and the paywall.
        ///
        /// It holds the same values as `Breath.inhale` on purpose: the icon is
        /// the breathing shape at rest, so the app's own colour *is* the
        /// inhale's. It matches `settle` only in the dark appearance — the two
        /// parted company in light, where a goal accent has to carry a goal
        /// word at AA and Brand has to match the icon ring. Kept as its own
        /// token so the pairs can move independently without touching a call
        /// site.
        public static let brand = ColorToken.accentBrand.color
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
        /// Warm rose — the register a small child is spoken to in.
        ///
        /// The one accent a route rather than a goal reaches for, so it answers
        /// to a different axis and gets its own token rather than borrowing
        /// `spark`: a goal and a register can both change, and an alias would
        /// make retuning the energising accent silently retune the children's
        /// screen. Rose because the warm end of this palette was already spoken
        /// for — amber is energy and rust is a warning — and a third colour in
        /// that arc would have read as one of them.
        public static let play = ColorToken.accentPlay.color
    }

    /// The breath's own colours — what the moving shape is made of, on every
    /// surface that draws one.
    ///
    /// Phase colour and goal colour answer to different axes and must never
    /// trade places: a goal accent colours the surround — a card edge, a
    /// filter pill, a history dot — and the breath core stays the phase colour
    /// everywhere, so the shape means one thing wherever it appears. `inhale`
    /// and `hold` sit at one lightness and chroma, 65° apart in hue, because
    /// the two phases are equals rather than a hierarchy.
    public enum Breath {
        /// The inhale, and the core of the breathing shape on every surface.
        /// Holds `Accent.brand`'s values on purpose — the icon is this shape
        /// at rest.
        public static let inhale = ColorToken.breathInhale.color
        /// Holds, everywhere they appear: the hold ring, a figure's hold
        /// stroke, a rhythm bar's hold segment.
        public static let hold = ColorToken.breathHold.color
        /// Vapour — the exhale is a fading of the inhale rather than a third
        /// hue, so this is drawn at low opacities and never carries state on
        /// its own.
        public static let exhale = ColorToken.breathExhale.color
    }
}
