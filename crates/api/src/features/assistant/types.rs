//! The assistant's domain vocabulary, and the numbers that bound what it
//! costs. The prose here — what a goal or an experience level is called — is
//! shared by the prompt and the rule-based fallback on purpose: the
//! assistant's words should be the same whoever wrote the sentence.

use crate::features::entitlement::types::Tier;
use crate::features::profile::types::{BirthYearBand, ExperienceLevel, Gender};
use crate::features::technique::types::TechniqueGoal;

/// What a goal is called in prose.
///
/// Shared with `super::fallback`, which writes the rule-based reasons: the
/// assistant's vocabulary for a goal should be the same whether a model or this
/// server wrote the sentence.
pub const fn goal_phrase(goal: TechniqueGoal) -> &'static str {
    match goal {
        TechniqueGoal::Calm => "settle in the moment",
        TechniqueGoal::Sleep => "wind down towards sleep",
        TechniqueGoal::Energy => "raise their energy",
        TechniqueGoal::Reset => "reset after a spike",
        TechniqueGoal::Focus => "hold their focus",
    }
}

/// What an experience level is called in prose. `None` is a real state — nobody
/// has been asked — and reads as such rather than as a beginner.
pub const fn experience_phrase(level: Option<ExperienceLevel>) -> &'static str {
    match level {
        Some(ExperienceLevel::New) => "new to breathwork",
        Some(ExperienceLevel::Occasional) => "has tried it, without a routine",
        Some(ExperienceLevel::Regular) => "practises regularly",
        None => "unknown — they have not been asked",
    }
}

/// What a birth-year band is called in prose. Decade coarseness is deliberate —
/// the model calibrates a breath-test reading with it, and a finer age would
/// sharpen nothing but the privacy cost.
pub const fn band_phrase(band: BirthYearBand) -> &'static str {
    match band {
        BirthYearBand::BornBefore1960 => "born before 1960",
        BirthYearBand::Born1960s => "born in the 1960s",
        BirthYearBand::Born1970s => "born in the 1970s",
        BirthYearBand::Born1980s => "born in the 1980s",
        BirthYearBand::Born1990s => "born in the 1990s",
        BirthYearBand::Born2000s => "born in the 2000s",
    }
}

/// What a gender is called in prose. "Rather not say" is `None` on the
/// snapshot and never reaches this function — absence is expressed by writing
/// no line at all, not by a phrase.
pub const fn gender_phrase(gender: Gender) -> &'static str {
    match gender {
        Gender::Female => "female",
        Gender::Male => "male",
        Gender::NonBinary => "non-binary",
    }
}

/// The coarse BOLT bands the assistant reasons with, as each band's lower
/// edge in seconds — the published Oxygen Advantage bands (Patrick McKeown,
/// 2015): under 10 is very easily unsettled, 10–20 building, 20–30 solid,
/// 30–40 strong, 40 the programme's target. Drives `prompt::catalogue_prefix`.
pub const BOLT_BAND_BUILDING: u32 = 10;
pub const BOLT_BAND_SOLID: u32 = 20;
pub const BOLT_BAND_STRONG: u32 = 30;
pub const BOLT_BAND_TARGET: u32 = 40;

/// The coarse resting-rate bands, as each band's lower edge in breaths a
/// minute. Clinical, unlike the BOLT bands: 12–20 is the adult resting range
/// (American Lung Association). The bottom band is the resonance frequency —
/// around six, where slow breathing maximises RSA and baroreflex sensitivity
/// (Russo et al. 2017; Zaccaro et al. 2018) — the aim, not a rate to get under.
pub const RESTING_RATE_BAND_SLOW: u32 = 7;
pub const RESTING_RATE_BAND_TYPICAL: u32 = 12;
pub const RESTING_RATE_BAND_BRISK: u32 = 21;

/// The physiological ranges a client-supplied health summary must sit inside
/// — wide on purpose: the bounds of what a wrist sensor could plausibly have
/// measured on a living wearer, not clinical ranges; outside them is an
/// artefact or a fabricated request. The breathing floor matches
/// `journey::resting_rate`'s: below four, somebody was holding, not breathing.
const RESTING_HR_BPM_RANGE: std::ops::RangeInclusive<i32> = 25..=150;
const RESTING_HR_TREND_BPM_RANGE: std::ops::RangeInclusive<i32> = -40..=40;
const HRV_SDNN_MS_RANGE: std::ops::RangeInclusive<i32> = 1..=300;
const HRV_SDNN_TREND_MS_RANGE: std::ops::RangeInclusive<i32> = -150..=150;
const SLEEPING_BREATHS_RANGE: std::ops::RangeInclusive<i32> = 4..=40;
const SLEEPING_BREATHS_TREND_RANGE: std::ops::RangeInclusive<i32> = -20..=20;

/// The coarse trends a request carried, after clamping — what
/// `prompt::health_lines` renders and nothing else reads. Special-category
/// data (GDPR Art. 9): built per request, dropped with it, never persisted,
/// and deliberately no `Debug`/`Display`, so "health values never reach the
/// log" is a compile error. A trend never appears without its mean.
pub struct HealthContext {
    pub resting_hr_bpm: Option<i32>,
    pub resting_hr_trend_bpm: Option<i32>,
    pub hrv_sdnn_ms: Option<i32>,
    pub hrv_sdnn_trend_ms: Option<i32>,
    pub sleeping_breaths_per_minute: Option<i32>,
    pub sleeping_breaths_trend: Option<i32>,
}

/// One metric as the wire carries it: a rounded 7-day mean and the delta
/// against the weeks before it, either possibly absent. A pair rather than
/// loose arguments because a mean and its trend are only meaningful together
/// — enforcing that is [`clamped_metric`]'s whole job.
pub type Metric = (Option<i32>, Option<i32>);

impl HealthContext {
    /// The context these three metrics support, clamped field by field.
    /// Out-of-range values drop the field, never the request — a broken
    /// sensor should not silence the coach. A trend whose mean was dropped
    /// falls with it, and a context left with no mean is `None`: absent and
    /// all-dropped must be indistinguishable, both rendering no HEALTH block.
    pub fn clamped(resting_hr: Metric, hrv_sdnn: Metric, sleeping_breaths: Metric) -> Option<Self> {
        let (resting_hr_bpm, resting_hr_trend_bpm) =
            clamped_metric(resting_hr, RESTING_HR_BPM_RANGE, RESTING_HR_TREND_BPM_RANGE);
        let (hrv_sdnn_ms, hrv_sdnn_trend_ms) =
            clamped_metric(hrv_sdnn, HRV_SDNN_MS_RANGE, HRV_SDNN_TREND_MS_RANGE);
        let (sleeping_breaths_per_minute, sleeping_breaths_trend) = clamped_metric(
            sleeping_breaths,
            SLEEPING_BREATHS_RANGE,
            SLEEPING_BREATHS_TREND_RANGE,
        );

        (resting_hr_bpm.is_some() || hrv_sdnn_ms.is_some() || sleeping_breaths_per_minute.is_some())
            .then_some(Self {
                resting_hr_bpm,
                resting_hr_trend_bpm,
                hrv_sdnn_ms,
                hrv_sdnn_trend_ms,
                sleeping_breaths_per_minute,
                sleeping_breaths_trend,
            })
    }
}

/// One metric through the clamp: the mean survives only inside its range, and
/// the trend survives only inside its own range *and* alongside a surviving
/// mean — the drop-with-its-mean coupling lives here so a metric added later
/// cannot forget it.
fn clamped_metric(
    (mean, trend): Metric,
    mean_range: std::ops::RangeInclusive<i32>,
    trend_range: std::ops::RangeInclusive<i32>,
) -> Metric {
    let mean = mean.filter(|value| mean_range.contains(value));
    (
        mean,
        mean.and(trend.filter(|value| trend_range.contains(value))),
    )
}

/// The separator between a slug and its reason in a model's reply. A pipe:
/// colons and commas occur inside the sentence on the right and a pipe does
/// not, so `split_once` cannot be fooled by ordinary English. Shared by the
/// instruction and the parser — two copies could disagree, and that would
/// look exactly like a model that stopped following instructions.
pub const FIELD_SEPARATOR: char = '|';

/// One technique the assistant is putting forward, and the sentence that
/// justifies it. The slug is always one the catalogue serves: a model's
/// output reaches this type only after `parse_recommendations` checked it,
/// so nothing above the parser has to wonder whether a slug is real.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Recommendation {
    pub technique_slug: String,
    pub reason: String,
}

/// How many techniques one recommendation carries.
///
/// Three. It is a nudge towards the next session, and a person who wanted the
/// whole catalogue would have opened the catalogue.
pub const RECOMMENDATION_COUNT: usize = 3;

/// Model calls one person may make per UTC day, or `None` for a tier that
/// does not buy the model. One shared pool; fifty covers a real conversation,
/// and the paid ceiling is a spend cap, not a tier gate. **`None` for Free is
/// the coach's gate**, paired with `OndKit`'s `SubscriptionTier.assistant` —
/// shipped apart they produce the "ask again later, forever" loop.
pub const fn daily_model_calls(tier: Tier) -> Option<i32> {
    match tier {
        Tier::Free => None,
        Tier::Plus => Some(50),
    }
}

/// The output ceiling on a recommendation call.
///
/// Three slugs and three sentences fit comfortably; a model that keeps writing
/// is cut off, and the parser drops whatever the truncation mangled.
pub const RECOMMENDATION_MAX_TOKENS: i32 = 400;

/// The output ceiling on one chat reply. Headroom for a tool call matters:
/// an `offer_exercise` block spends output tokens on its input JSON, and a
/// ceiling that truncated it mid-JSON would cost the person the card. The
/// prose is a few short paragraphs; anything longer is a lecture.
pub const CHAT_MAX_TOKENS: i32 = 850;

/// The most history turns one chat call reads, keeping the newest.
/// Truncation is silent — "your transcript is long" is not an answer. Twenty
/// turns is more context than a coaching answer draws on, and it bounds the
/// input spend the way `CHAT_MAX_TOKENS` bounds the output.
pub const MAX_CHAT_TURNS: usize = 20;

/// The longest message — new or replayed as history — one chat call accepts,
/// in characters. A bound rather than a truncation, unlike [`MAX_CHAT_TURNS`]:
/// cutting a message mid-sentence would have the coach answer something the
/// person did not say, so an over-long one is `INVALID_ARGUMENT`. Sized like
/// the intent note — generous for typing, useless for prompt smuggling.
pub const MAX_CHAT_MESSAGE_CHARS: usize = 1000;

#[cfg(test)]
mod tests {
    use super::*;

    /// In-range values pass through untouched, trends included.
    #[test]
    fn a_plausible_context_survives_clamping_whole() {
        let context = HealthContext::clamped(
            (Some(62), Some(4)),
            (Some(45), Some(-6)),
            (Some(14), Some(-1)),
        )
        .expect("a plausible context is kept");

        assert_eq!(context.resting_hr_bpm, Some(62));
        assert_eq!(context.resting_hr_trend_bpm, Some(4));
        assert_eq!(context.hrv_sdnn_ms, Some(45));
        assert_eq!(context.hrv_sdnn_trend_ms, Some(-6));
        assert_eq!(context.sleeping_breaths_per_minute, Some(14));
        assert_eq!(context.sleeping_breaths_trend, Some(-1));
    }

    /// The bounds are inclusive: a value on either edge is evidence, and
    /// clamping it away would make the documented range a lie by one unit.
    #[test]
    fn the_range_edges_are_kept() {
        let low = HealthContext::clamped(
            (Some(25), Some(-40)),
            (Some(1), Some(-150)),
            (Some(4), Some(-20)),
        )
        .expect("the low edges are in range");
        assert_eq!(low.resting_hr_bpm, Some(25));
        assert_eq!(low.resting_hr_trend_bpm, Some(-40));
        assert_eq!(low.hrv_sdnn_ms, Some(1));
        assert_eq!(low.hrv_sdnn_trend_ms, Some(-150));
        assert_eq!(low.sleeping_breaths_per_minute, Some(4));
        assert_eq!(low.sleeping_breaths_trend, Some(-20));

        let high = HealthContext::clamped(
            (Some(150), Some(40)),
            (Some(300), Some(150)),
            (Some(40), Some(20)),
        )
        .expect("the high edges are in range");
        assert_eq!(high.resting_hr_bpm, Some(150));
        assert_eq!(high.resting_hr_trend_bpm, Some(40));
        assert_eq!(high.hrv_sdnn_ms, Some(300));
        assert_eq!(high.hrv_sdnn_trend_ms, Some(150));
        assert_eq!(high.sleeping_breaths_per_minute, Some(40));
        assert_eq!(high.sleeping_breaths_trend, Some(20));
    }

    /// An implausible value drops its own field and nothing else — the request
    /// still carries a question, and one broken sensor must not silence the
    /// rest of the summary.
    #[test]
    fn an_implausible_value_drops_only_its_field() {
        let context = HealthContext::clamped((Some(300), Some(4)), (Some(45), None), (None, None))
            .expect("the surviving metric keeps the context alive");

        assert_eq!(context.resting_hr_bpm, None);
        assert_eq!(context.hrv_sdnn_ms, Some(45));
    }

    /// A trend is a delta against its own mean, so a dropped mean takes the
    /// trend with it even when the trend itself is in range.
    #[test]
    fn a_trend_falls_with_its_mean() {
        let context =
            HealthContext::clamped((Some(300), Some(4)), (Some(45), Some(-6)), (None, None))
                .expect("the HRV metric survives");

        assert_eq!(context.resting_hr_bpm, None);
        assert_eq!(
            context.resting_hr_trend_bpm, None,
            "a delta against a dropped mean is a number with no referent"
        );
        assert_eq!(context.hrv_sdnn_trend_ms, Some(-6));
    }

    /// An out-of-range trend drops alone; its mean is independent evidence.
    #[test]
    fn an_implausible_trend_leaves_its_mean() {
        let context = HealthContext::clamped(
            (Some(62), Some(90)),
            (Some(45), Some(200)),
            (Some(14), Some(90)),
        )
        .expect("both means survive");

        assert_eq!(context.resting_hr_bpm, Some(62));
        assert_eq!(context.resting_hr_trend_bpm, None);
        assert_eq!(context.hrv_sdnn_ms, Some(45));
        assert_eq!(context.hrv_sdnn_trend_ms, None);
        assert_eq!(context.sleeping_breaths_per_minute, Some(14));
        assert_eq!(context.sleeping_breaths_trend, None);
    }

    /// A context with no surviving mean is no context at all — downstream must
    /// not be able to tell "sent nothing" from "sent nothing usable".
    #[test]
    fn a_context_with_no_surviving_mean_is_none() {
        assert!(HealthContext::clamped((None, None), (None, None), (None, None)).is_none());
        assert!(
            HealthContext::clamped((Some(999), Some(4)), (Some(0), Some(-6)), (Some(1), None))
                .is_none()
        );
        assert!(
            HealthContext::clamped((None, Some(4)), (None, Some(-6)), (None, Some(-1))).is_none(),
            "trends alone carry no mean to anchor them"
        );
    }

    /// The breathing rate holds a context up on its own — not a restatement
    /// of the drops-only-its-field test: somebody who wears the watch to bed
    /// but not to train has overnight breathing and too little heart data,
    /// and dropping their block for want of a heartbeat would lose the one
    /// figure the practice actually moves.
    #[test]
    fn the_breathing_rate_alone_keeps_the_context() {
        let context = HealthContext::clamped((None, None), (None, None), (Some(13), Some(-2)))
            .expect("breathing alone is evidence");

        assert_eq!(context.sleeping_breaths_per_minute, Some(13));
        assert_eq!(context.sleeping_breaths_trend, Some(-2));
    }
}
