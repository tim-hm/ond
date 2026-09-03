//! The builders are the only way to make a phase, so a phase that names a
//! passage it cannot have does not compile. Each enum mirrors a Postgres enum
//! declared in the migrations. A local copy, because this crate creates the
//! schema and must not depend on `api`.

use serde::Serialize;

/// Mirrors the `technique_goal` Postgres enum declared in `0001_init.sql`.
///
/// A local copy, because this crate creates the schema and must not depend on
/// `api`. It binds a value the database's own type system accepts, so a
/// mistyped label is a compile error rather than a failed migration.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "technique_goal", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum TechniqueGoal {
    Calm,
    Sleep,
    Energy,
    Reset,
    Focus,
}

/// Mirrors the `phase_kind` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "phase_kind", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum PhaseKind {
    Inhale,
    HoldIn,
    Exhale,
    HoldOut,
}

/// `#[cfg(test)]` because seeding never asks the question — the constructors
/// below decide a phase's kind, and only the rules checking them care which
/// side of this line it fell. Without the gate it is dead code in the shipped
/// binary, which `check:rs` refuses.
#[cfg(test)]
impl PhaseKind {
    /// Whether air moves during this phase. Named rather than matched inline,
    /// because the negated form ("everything that is not either hold") is the
    /// one a reader has to invert in their head. The same predicate as
    /// `technique::types::PhaseKind::is_breathing`, restated because `migrate`
    /// does not depend on `api`.
    pub(super) const fn is_breathing(self) -> bool {
        matches!(self, Self::Inhale | Self::Exhale)
    }
}

/// Mirrors the `passage` Postgres enum, on the same terms as [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "passage", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum Passage {
    Nose,
    Mouth,
    LeftNostril,
    RightNostril,
}

/// Mirrors the `manner` Postgres enum, on the same terms as [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "manner", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum Manner {
    CurledTongue,
    PursedLips,
    Hum,
}

impl Manner {
    /// The one breath each shape can be made on. A second copy of the
    /// `technique_phases_manner_fits_its_breath` constraint: the constraint
    /// catches a row however it arrives, and this catches the seed at compile
    /// time, because `TECHNIQUES` is a `const` and the `assert!` reading this
    /// runs during its evaluation.
    pub(super) const fn shapes(self, kind: PhaseKind, passage: Passage) -> bool {
        matches!(
            (self, kind, passage),
            (Self::CurledTongue, PhaseKind::Inhale, Passage::Mouth)
                | (Self::PursedLips, PhaseKind::Exhale, Passage::Mouth)
                | (Self::Hum, PhaseKind::Exhale, Passage::Nose)
        )
    }
}

/// Mirrors the `delivery_surface` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "delivery_surface", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum DeliverySurface {
    FullScreen,
    Discreet,
}

/// Mirrors the `copy_register` Postgres enum, on the same terms as
/// [`TechniqueGoal`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "copy_register", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum CopyRegister {
    Plain,
    Playful,
}

/// Mirrors the `evidence_grade` Postgres enum, on the same terms as
/// [`CopyRegister`].
///
/// The rubric each entry was graded against, and why there are two grades and
/// no `Strong`, are in `docs/product/breathing-science.md` §2.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type, Serialize)]
#[sqlx(type_name = "evidence_grade", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum EvidenceGrade {
    Moderate,
    Limited,
}

/// How the items after a reading lead are presented.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(super) enum ReadingListStyle {
    None,
    Bullets,
    Numbered,
}

/// A short lead and, where the copy is genuinely list-shaped, its items.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ReadingContentSeed {
    pub(super) lead: &'static str,
    pub(super) items: &'static [&'static str],
    pub(super) list_style: ReadingListStyle,
}

impl ReadingContentSeed {
    /// A paragraph with no list.
    pub(super) const fn prose(lead: &'static str) -> Self {
        Self {
            lead,
            items: &[],
            list_style: ReadingListStyle::None,
        }
    }

    /// A lead followed by unordered points.
    pub(super) const fn bullets(lead: &'static str, items: &'static [&'static str]) -> Self {
        Self {
            lead,
            items,
            list_style: ReadingListStyle::Bullets,
        }
    }

    /// A lead followed by steps whose order matters.
    pub(super) const fn numbered(lead: &'static str, items: &'static [&'static str]) -> Self {
        Self {
            lead,
            items,
            list_style: ReadingListStyle::Numbered,
        }
    }

    /// Whether the catalogue has nothing to say in this slot.
    pub(super) const fn is_empty(self) -> bool {
        self.lead.is_empty() && self.items.is_empty()
    }

    /// The complete plain-text form sent to clients that predate the structure.
    pub(super) fn plain_text(self) -> String {
        let mut text = self.lead.to_owned();

        if !self.items.is_empty() {
            if !text.is_empty() {
                text.push_str("\n\n");
            }

            for (index, item) in self.items.iter().enumerate() {
                if index > 0 {
                    text.push('\n');
                }
                match self.list_style {
                    ReadingListStyle::None => text.push_str(item),
                    ReadingListStyle::Bullets => {
                        text.push_str("• ");
                        text.push_str(item);
                    }
                    ReadingListStyle::Numbered => {
                        text.push_str(&(index + 1).to_string());
                        text.push_str(". ");
                        text.push_str(item);
                    }
                }
            }
        }

        text
    }
}

/// One phase: its kind, where the air goes, the curated default, and the range a
/// dial may move it within.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct PhaseSeed {
    pub(super) kind: PhaseKind,
    /// `None` exactly for a hold, matching the column's `CHECK`. Unreachable in
    /// any other combination because the four constructors below are the only
    /// way to build one of these.
    pub(super) passage: Option<Passage>,
    /// How the breath is shaped, where the shape is what the technique turns on.
    /// `None` means "shaped no particular way", and most phases are. Unreachable
    /// on a breath it cannot shape: the two shaped constructors below check it
    /// against the column's own `CHECK` while `TECHNIQUES` is const-evaluated.
    pub(super) manner: Option<Manner>,
    pub(super) duration_ms: i32,
    pub(super) min_duration_ms: i32,
    pub(super) max_duration_ms: i32,
    /// The stillness closing this phase, the tap it plays and the line it
    /// speaks. `None` on each means the app works it out: the tempo gap, the
    /// `standard` tap, and the cue this phase's place implies. A table authors
    /// one only where the derived answer is wrong for the exercise.
    pub(super) turn_gap_ms: Option<i32>,
    pub(super) haptic_pattern: Option<&'static str>,
}

/// A run of cycles sharing one phase pattern.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct StageSeed {
    pub(super) phases: &'static [PhaseSeed],
    pub(super) cycles: i32,
    /// Whether the person ends this stage rather than the clock.
    pub(super) open_ended: bool,
}

/// One technique and the session it describes.
pub(super) struct TechniqueSeed {
    pub(super) slug: &'static str,
    pub(super) name: &'static str,
    /// A row's worth: what it does and when to reach for it, short enough that
    /// they fit in a list.
    pub(super) summary: &'static str,
    /// Why it works, as structured reading copy for the exercise's own screen.
    /// It sits beside `summary`, not as a longer version of it: one is a line in
    /// a list, the other is a page's opening argument. Lead with the likely
    /// benefit and use no more than three supporting points.
    /// `every_technique_opens_on_its_mechanism` requires one on every technique.
    pub(super) mechanism: ReadingContentSeed,
    /// How strong the case for this exercise actually is, as a verdict and list.
    /// It never repeats `mechanism`: the mechanism cites a trial to say the
    /// exercise is not folklore, and this sizes the same trial.
    /// `every_technique_names_its_evidence` requires two or three points. Say
    /// what was shown, why it matters here, and what is still missing.
    pub(super) evidence: ReadingContentSeed,
    /// The same judgement as `evidence`, in the one word a list row can carry.
    ///
    /// Seeded beside the evidence rather than inferred from it, so a rewritten
    /// sentence cannot quietly re-grade an exercise. Every curated technique
    /// carries one; `None` belongs to the exercises people write themselves.
    pub(super) evidence_grade: EvidenceGrade,
    /// The caution this technique carries, empty where it carries none. The
    /// phone renders it as a full-screen warning between Begin and the countdown
    /// (`TechniqueWarningView`). The person silences it against this exact text,
    /// so rewording a note re-asks everyone who put it away. Blanking a note
    /// removes that warning; the watch and the assistant fallback show none.
    pub(super) safety_note: &'static str,
    /// What to do with your body before the first breath, empty where the
    /// exercise asks for nothing. It is the part that does not change while the
    /// exercise runs, unlike the hint beside each breath. It is also where a
    /// shape offers an alternative: the cooling breath offers closed teeth to
    /// anybody whose tongue will not roll, which an enum case cannot say.
    pub(super) preparation: ReadingContentSeed,
    pub(super) goal: TechniqueGoal,
    pub(super) stages: &'static [StageSeed],
    /// How many times a default session repeats the whole stage list. Curated
    /// per technique, and one for everything that is a single cycle repeated —
    /// rounds only earn their name in a staged protocol.
    pub(super) recommended_rounds: i32,
    /// Whether this one is behind önd+. False for every technique at present:
    /// the whole catalogue is free while the featureset is still moving.
    /// Restoring the gate is typing `true` here. It is stated per technique with
    /// no default, so a new technique forces a decision.
    pub(super) requires_subscription: bool,
}

/// A phase with the dial range it may be moved within, inclusive. A range of a
/// single point means the phase is not adjustable, which is the honest
/// description of a hold the person ends themselves. There are six constructors
/// rather than one taking a kind, so a hold has nowhere to put a passage and a
/// breath cannot omit one.
pub(super) const fn inhale(passage: Passage, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    breath(PhaseKind::Inhale, passage, None, duration_ms, dial)
}

pub(super) const fn exhale(passage: Passage, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    breath(PhaseKind::Exhale, passage, None, duration_ms, dial)
}

/// A breath the exercise shapes as well as places. A separate constructor rather
/// than a sixth argument, because three phases in the catalogue are shaped and
/// thirty-eight are not. The passage is still passed even though each manner
/// implies one, so `Passage::Mouth` stays legible at the cooling breath's call
/// site, and the `assert!` makes a disagreement a compile error.
pub(super) const fn shaped_inhale(
    passage: Passage,
    manner: Manner,
    duration_ms: i32,
    dial: (i32, i32),
) -> PhaseSeed {
    assert!(
        manner.shapes(PhaseKind::Inhale, passage),
        "a manner on an inhale it cannot shape"
    );
    breath(PhaseKind::Inhale, passage, Some(manner), duration_ms, dial)
}

pub(super) const fn shaped_exhale(
    passage: Passage,
    manner: Manner,
    duration_ms: i32,
    dial: (i32, i32),
) -> PhaseSeed {
    assert!(
        manner.shapes(PhaseKind::Exhale, passage),
        "a manner on an exhale it cannot shape"
    );
    breath(PhaseKind::Exhale, passage, Some(manner), duration_ms, dial)
}

pub(super) const fn hold_in(duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    hold(PhaseKind::HoldIn, duration_ms, dial)
}

pub(super) const fn hold_out(duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    hold(PhaseKind::HoldOut, duration_ms, dial)
}

pub(super) const fn breath(
    kind: PhaseKind,
    passage: Passage,
    manner: Option<Manner>,
    duration_ms: i32,
    dial: (i32, i32),
) -> PhaseSeed {
    PhaseSeed {
        kind,
        passage: Some(passage),
        manner,
        duration_ms,
        min_duration_ms: dial.0,
        max_duration_ms: dial.1,
        turn_gap_ms: None,
        haptic_pattern: None,
    }
}

pub(super) const fn hold(kind: PhaseKind, duration_ms: i32, dial: (i32, i32)) -> PhaseSeed {
    PhaseSeed {
        kind,
        passage: None,
        // Air that is not moving has no shape to hold, which the column's
        // `CHECK` states by naming a breathing kind in every arm.
        manner: None,
        duration_ms,
        min_duration_ms: dial.0,
        max_duration_ms: dial.1,
        turn_gap_ms: None,
        haptic_pattern: None,
    }
}

/// The tap a phase plays where the derived one is wrong for it. Four names
/// rather than the client's five: a phase naming nothing already plays
/// `standard`, so the fifth is the absence. Stated as cases because the client
/// takes free text here and falls back silently on a name it does not know.
pub(super) enum HapticPattern {
    /// The second, stacked breath of a sigh.
    Sip,
    /// A breath out against resistance — pursed lips, or a hum.
    Press,
    /// The mark alone, for a phase too short to carry an envelope.
    Drum,
    /// The mark, then a reminder while a long hold runs.
    LongHold,
}

impl HapticPattern {
    /// Every id the client resolves, including the `standard` this set has no
    /// case for. A phase naming nothing already plays `standard`, so nothing
    /// authors it, and only the test checking an id against the set needs it.
    #[cfg(test)]
    pub(super) const RESOLVED: [&'static str; 5] = [
        "standard",
        Self::Sip.id(),
        Self::Press.id(),
        Self::Drum.id(),
        Self::LongHold.id(),
    ];

    pub(super) const fn id(self) -> &'static str {
        match self {
            Self::Sip => "sip",
            Self::Press => "press",
            Self::Drum => "drum",
            Self::LongHold => "long-hold",
        }
    }
}

/// What a phase authors on top of its shape, chained onto the constructors
/// above so a phase that authors nothing stays one line.
impl PhaseSeed {
    /// The stillness closing this phase, in milliseconds, where the body's turn
    /// is longer than tempo assumes: out of a full-lung hold, into a stacked
    /// breath, or through a mechanical change. Zero is a value and not an
    /// absence — a continuous rhythm turns without a pause on purpose. The gap
    /// is borrowed from the phase, so authoring one never lengthens a session.
    pub(super) const fn with_gap(mut self, milliseconds: i32) -> Self {
        self.turn_gap_ms = Some(milliseconds);
        self
    }

    pub(super) const fn with_haptic(mut self, pattern: HapticPattern) -> Self {
        self.haptic_pattern = Some(pattern.id());
        self
    }

    /// A phase of a rhythm that turns without a pause. The derived 25 ms would
    /// put a stutter in a rhythm whose whole physiology is that it has none,
    /// and an envelope under 1.5 s is noise with a tap buried in it. Bellows
    /// breath and the Wim Hof round breathing are the two.
    pub(super) const fn continuous(self) -> Self {
        self.with_gap(0).with_haptic(HapticPattern::Drum)
    }
}

pub(super) const fn stage(phases: &'static [PhaseSeed], cycles: i32) -> StageSeed {
    StageSeed {
        phases,
        cycles,
        open_ended: false,
    }
}

/// A stage the clock does not end. One cycle by definition: repeating a hold
/// the person is already in charge of ending means nothing.
pub(super) const fn open_ended_stage(phases: &'static [PhaseSeed]) -> StageSeed {
    StageSeed {
        phases,
        cycles: 1,
        open_ended: true,
    }
}

/// One question a beginner has, and the app's answer to it.
pub(super) struct FoundationSeed {
    pub(super) slug: &'static str,
    pub(super) question: &'static str,
    pub(super) answer: ReadingContentSeed,
}

/// A named moment and the prescription it resolves to.
///
/// Flat rather than holding a `PrescriptionSeed`: the four fields below the
/// copy *are* the prescription, and a nested struct would buy a name the wire
/// already carries at the cost of a second brace level per entry.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct OccasionSeed {
    pub(super) slug: &'static str,
    pub(super) name: &'static str,
    pub(super) summary: &'static str,
    /// The technique this routes to, by the slug in [`TECHNIQUES`]. A foreign
    /// key onto `techniques.slug`, so a typo here fails the seed rather than
    /// reaching a client as a route to nothing.
    pub(super) technique_slug: &'static str,
    /// The goal the moment borrows. Stated per occasion rather than read back
    /// through `technique_slug`, because what a moment is for must not move
    /// when a technique's primary grouping is re-curated.
    pub(super) goal: TechniqueGoal,
    pub(super) surface: DeliverySurface,
    pub(super) register: CopyRegister,
    /// A protocol-owned rhythm, in the technique's phase order. Empty keeps the
    /// exercise's curated durations; populated is valid only for one closed,
    /// cyclic stage and must name every phase. It carries durations and nothing
    /// else: a moment may re-time the breaths it borrows, but it cannot change
    /// where the air goes, how many phases there are, or what the copy says.
    pub(super) phase_durations_ms: &'static [i32],
    /// The protocol's caution, empty where the exercise says all that needs
    /// saying. The two divide on whether the hazard is the breathing or the
    /// moment: the breathlessness triage on `when-youre-winded` and the child
    /// caution on `with-your-child` are hazards of the situation, not of the
    /// breath. `the_protocols_that_need_a_warning_carry_one` pins the set.
    pub(super) safety_note: &'static str,
    /// What this occasion asks for, as a target a client fits whole cycles
    /// into rather than a stopwatch that cuts a breath short.
    pub(super) duration_ms: i32,
}

/// One rung of the Start here progression.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ProgressionStepSeed {
    pub(super) technique_slug: &'static str,
    /// Why this one at this point — what makes the order a progression rather
    /// than a list.
    pub(super) note: &'static str,
}
