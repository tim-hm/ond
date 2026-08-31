//! The half of the prompt every caller shares, and the only half worth
//! caching. Built from data that changes only when the seed does, so the
//! catalogue, routes and measurement bands cannot drift from what the app
//! shows. What is written out rather than derived — persona, how-to-write
//! rules, card etiquette, refusals — is here because no database holds it.

use std::fmt::Write as _;
use std::sync::{Arc, LazyLock, OnceLock};

use super::super::types::{
    BOLT_BAND_BUILDING, BOLT_BAND_SOLID, BOLT_BAND_STRONG, BOLT_BAND_TARGET,
    RESTING_RATE_BAND_BRISK, RESTING_RATE_BAND_SLOW, RESTING_RATE_BAND_TYPICAL, goal_phrase,
};
use crate::features::technique::types::{
    DeliverySurface, PhaseKind, PlayableStage, Reference, Technique,
};

/// The instructions and the catalogue: the same bytes on every call. Note
/// what is absent — no profile, no practice, no name, no note: one personal
/// detail here would make the prefix per-caller and quietly turn a cache read
/// back into a full-price write. The measurement briefings stay on this side
/// because they are how to *read* a rate and a pause, never anybody's figures.
pub fn catalogue_prefix(catalogue: &[Technique], reference: &Reference) -> String {
    let typical_top = RESTING_RATE_BAND_BRISK - 1;
    let aiming_at = RESTING_RATE_BAND_SLOW - 1;

    render(&[
        ("catalogue", &catalogue_lines(catalogue)),
        ("moments", &reference_lines(reference)),
        ("resting_typical", &RESTING_RATE_BAND_TYPICAL.to_string()),
        ("resting_typical_top", &typical_top.to_string()),
        ("resting_aim", &aiming_at.to_string()),
        ("bolt_building", &BOLT_BAND_BUILDING.to_string()),
        ("bolt_solid", &BOLT_BAND_SOLID.to_string()),
        ("bolt_strong", &BOLT_BAND_STRONG.to_string()),
        ("bolt_target", &BOLT_BAND_TARGET.to_string()),
    ])
}

/// [`catalogue_prefix`]'s output, rendered on the first call and then handed
/// out by refcount. One cache per transport instance rather than a process
/// global, for [`CuratedCache`](crate::features::technique::cache::CuratedCache)'s
/// reason: each e2e stack derives from its own database, and a global would
/// serve one stack's catalogue against another's.
pub struct PrefixCache(OnceLock<Arc<str>>);

impl PrefixCache {
    pub const fn new() -> Self {
        Self(OnceLock::new())
    }

    pub fn get(&self, catalogue: &[Technique], reference: &Reference) -> Arc<str> {
        Arc::clone(
            self.0
                .get_or_init(|| catalogue_prefix(catalogue, reference).into()),
        )
    }
}

/// The prompt's prose, verbatim and compiled in. A file rather than a string
/// literal because it is edited and read as writing: a multi-line literal's
/// escaping made a paragraph break something you had to spell. `include_str!`
/// means there is nothing to deploy and nothing to read at runtime.
const TEMPLATE: &str = include_str!("copy/prefix.md");

/// [`TEMPLATE`] with its comments gone, derived once for the process — per
/// request this was a fifth of the prompt rebuilt on every question. Comments
/// drop by whole lines, so a `<!--` inside a paragraph is prose. Blank lines
/// around a dropped comment are deduplicated: the output is independent of a
/// formatter leaving one under a `-->`, and the prompt cannot open blank.
static TEXT: LazyLock<String> = LazyLock::new(|| {
    let mut out = String::with_capacity(TEMPLATE.len());
    let mut in_comment = false;

    for line in TEMPLATE.lines() {
        // Trimmed both ends, not just the leading one: a single space after a
        // closing `-->` would otherwise leave the strip inside the comment for
        // the rest of the file, silently taking the refusals with it. Nothing
        // cleans trailing whitespace here — this directory is exempt from every
        // formatter in the repo — so the one place that could catch it is here.
        let trimmed = line.trim();
        if in_comment || trimmed.starts_with("<!--") {
            in_comment = !trimmed.ends_with("-->");
            continue;
        }
        if trimmed.is_empty() && (out.is_empty() || out.ends_with("\n\n")) {
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }

    out
});

/// Fills [`TEXT`]'s `{{ name }}` slots in one pass. No error path: this reads
/// the one constant it is proved against, so the placeholder test renders once
/// and proves every caller forever. One pass, not a `replace` per slot, keeps
/// a slot's *value* from being scanned for later slots; an unknown name is left
/// standing so the test forbidding `{{` names it. Values trim trailing whitespace.
fn render(slots: &[(&str, &str)]) -> String {
    let mut out = String::with_capacity(TEXT.len() * 2);
    let mut rest = TEXT.as_str();

    while let Some(open) = rest.find("{{") {
        let Some(close) = rest[open..].find("}}").map(|end| open + end + 2) else {
            break;
        };

        out.push_str(&rest[..open]);
        let name = rest[open + 2..close - 2].trim();
        match slots.iter().find(|(slot, _)| *slot == name) {
            Some((_, value)) => out.push_str(value.trim_end()),
            None => out.push_str(&rest[open..close]),
        }
        rest = &rest[close..];
    }

    out.push_str(rest);
    out
}

/// Every technique as one line each; `render` takes the trailing newline off,
/// so spacing around the slot stays the template's business. The caution sits
/// before the mechanism, and the mechanism is flattened by [`one_line`]:
/// every seeded mechanism is several paragraphs, and interpolating one raw
/// stranded a caution ninety words below the slug it belongs to.
fn catalogue_lines(catalogue: &[Technique]) -> String {
    let mut lines = String::new();

    for technique in catalogue {
        // `write!` into a String is infallible; the `Write` import is what makes
        // the macro usable at all.
        let _ = writeln!(
            lines,
            "- {} | helps them {} | {} | pattern: {}{} | why it works: {}",
            technique.slug,
            goal_phrase(technique.goal),
            technique.summary,
            pattern_clause(technique),
            caution_clause(technique),
            one_line(&technique.mechanism)
        );
    }

    lines
}

/// Curated prose as one line, so interpolating it into a line-per-entry block
/// cannot break the block. Collapsing every whitespace run is what makes it
/// total: no input produces a newline, and the model loses the paragraphing
/// of a description and nothing else.
pub(super) fn one_line(prose: &str) -> String {
    prose.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// One technique's playable shape as a clause of its catalogue line: phases
/// with durations and allowed ranges in seconds, cycle counts, and rounds.
/// This is what makes the offer's parameters *possible* — the tool's ranges
/// mean nothing to a model never shown the shape it is adjusting.
fn pattern_clause(technique: &Technique) -> String {
    let stages = technique
        .stages
        .iter()
        .map(stage_clause)
        .collect::<Vec<_>>()
        .join(", then ");

    let rounds = technique.recommended_rounds;
    let plural = if rounds == 1 { "round" } else { "rounds" };
    format!("{stages}; {rounds} {plural}")
}

/// The app's own curated routes, as blocks of the cached prefix. Mappings
/// rather than copy: the coach and the screens must agree, and the seeded
/// wording is provisional ([`Occasion`](crate::features::technique::types::Occasion)).
/// The foundations are an index — questions, no answers — so the model knows
/// the app holds a position and stays in that lane, at a fraction of the tokens.
pub(super) fn reference_lines(reference: &Reference) -> String {
    let mut lines = String::new();

    if !reference.occasions.is_empty() {
        lines.push_str(
            "MOMENTS (the app's own entry points, on their own tab — a \
             person may have arrived from one of these)\n",
        );
        for occasion in &reference.occasions {
            let rhythm = if occasion.phase_durations_ms.is_empty() {
                String::new()
            } else {
                format!(
                    ", moment rhythm {}",
                    occasion
                        .phase_durations_ms
                        .iter()
                        .map(|duration| format!("{duration}ms"))
                        .collect::<Vec<_>>()
                        .join("/")
                )
            };
            let caution = if occasion.safety_note.is_empty() {
                String::new()
            } else {
                format!(", caution: {}", occasion.safety_note)
            };
            let _ = writeln!(
                lines,
                "- {} → {}, {} minutes, {}{}{}",
                occasion.slug,
                occasion.technique_slug,
                occasion.duration_ms / 60_000,
                match occasion.surface {
                    DeliverySurface::FullScreen => "full screen",
                    // The distinction the coach could not previously express at
                    // all: a session somebody can run without their phone
                    // announcing it.
                    DeliverySurface::Discreet => "discreet, for doing unnoticed",
                },
                rhythm,
                caution
            );
        }
    }

    if !reference.progression.is_empty() {
        let slugs = reference
            .progression
            .iter()
            .map(|step| step.technique_slug.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        let _ = writeln!(
            lines,
            "\nStart here, the curated order for a beginner: {slugs}"
        );
    }

    if !reference.foundations.is_empty() {
        lines.push_str(
            "\nFOUNDATIONS (questions the app answers in its own words, on its \
             own screen; cover the same ground in the same spirit, and never \
             contradict one)\n",
        );
        for topic in &reference.foundations {
            let _ = writeln!(lines, "- {}: {}", topic.slug, topic.question);
        }
    }

    lines
}

/// Whole hours since the last session, in the coarse words a coach would use
/// — deliberately vaguer the further back: a model handed "43 hours" will say
/// "43 hours". Days rather than a date, because a date needs a time zone and
/// this figure is chosen precisely for needing none.
pub(super) fn recency_phrase(hours: u32) -> String {
    match hours {
        0 => "within the hour".to_owned(),
        1 => "about an hour ago".to_owned(),
        2..=23 => format!("about {hours} hours ago"),
        24..=47 => "about a day ago".to_owned(),
        _ => format!("about {} days ago", hours / 24),
    }
}

/// One technique's curated caution as a clause of its catalogue line, or
/// nothing for the majority that carry none. Deliberately not a count — the
/// catalogue grows, and the noted set is pinned by a seed test that cannot
/// rot quietly. Absence is the absence of a clause, never an empty field: a
/// model shown `caution: ` with nothing after it has been told there is one.
fn caution_clause(technique: &Technique) -> String {
    if technique.safety_note.is_empty() {
        String::new()
    } else {
        format!(" | caution: {}", technique.safety_note)
    }
}

fn stage_clause(stage: &PlayableStage) -> String {
    let phases = stage
        .phases
        .iter()
        .map(|phase| {
            format!(
                "{} {}s ({}–{})",
                match phase.kind {
                    PhaseKind::Inhale => "inhale",
                    PhaseKind::HoldIn => "hold in",
                    PhaseKind::Exhale => "exhale",
                    PhaseKind::HoldOut => "hold out",
                },
                seconds(phase.duration_ms),
                seconds(phase.min_duration_ms),
                seconds(phase.max_duration_ms)
            )
        })
        .collect::<Vec<_>>()
        .join(", ");

    if stage.open_ended {
        format!("{phases}, open-ended")
    } else {
        format!("{phases} × {} cycles", stage.cycles)
    }
}

/// Milliseconds as the seconds the prompt and the tool schema speak in —
/// `4000` reads `4`, `1500` reads `1.5`.
pub(super) fn seconds(ms: i32) -> String {
    format!("{}", f64::from(ms) / 1000.0)
}

/// The server-worded annotation appended to a history turn that carried an
/// exercise offer. Built from the *resolved* technique's name and never the
/// wire slug: the wire value is client free text, and this line is the only
/// shape in which a past offer ever reaches the prompt.
pub fn offered_line(technique: &Technique) -> String {
    format!(
        "\n\n[Here you offered to start the {} exercise.]",
        technique.name
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::technique::types::{
        FoundationHeading, Occasion, OccasionSlug, ProgressionStep, TechniqueGoal, TechniqueSlug,
    };

    fn technique_slug(slug: &str) -> TechniqueSlug {
        TechniqueSlug::parse("slug", slug).expect("a fixture slug")
    }

    fn occasion_slug(slug: &str) -> OccasionSlug {
        OccasionSlug::parse("slug", slug).expect("a fixture slug")
    }

    fn catalogue() -> Vec<Technique> {
        ["box-breathing", "four-seven-eight"]
            .into_iter()
            .map(|slug| Technique::test(slug, TechniqueGoal::Calm))
            .collect()
    }

    fn reference() -> Reference {
        Reference {
            occasions: vec![Occasion {
                slug: occasion_slug("before-a-presentation"),
                technique_slug: technique_slug("box-breathing"),
                surface: DeliverySurface::FullScreen,
                duration_ms: 180_000,
                phase_durations_ms: vec![],
                safety_note: String::new(),
            }],
            progression: vec![ProgressionStep {
                technique_slug: technique_slug("box-breathing"),
            }],
            foundations: vec![FoundationHeading {
                slug: "nose-or-mouth".to_owned(),
                question: "Nose or mouth?".to_owned(),
            }],
        }
    }

    /// The prefix is what the provider caches, so it must not vary with the
    /// caller. A profile field leaking into it would turn every request into a
    /// fresh cache write, which is invisible in behaviour and visible only on
    /// the bill.
    #[test]
    fn the_cached_prefix_is_the_same_for_everyone() {
        let catalogue = catalogue();
        let prefix = catalogue_prefix(&catalogue, &reference());

        assert_eq!(prefix, catalogue_prefix(&catalogue, &reference()));
        for technique in &catalogue {
            assert!(
                prefix.contains(technique.slug.as_str()),
                "the catalogue carries `{}`",
                technique.slug
            );
        }

        // The static briefing rides on the cached side of the boundary: how to
        // read a score is the same for everyone, only the score is personal.
        assert!(
            prefix.contains("comfortable-pause result"),
            "the comfortable-pause briefing is in the prefix"
        );
        assert!(
            prefix.contains("never to gatekeep"),
            "the calibration clause is in the prefix"
        );
        assert!(
            prefix.contains("say so plainly"),
            "the disagreement instruction is in the prefix"
        );
        assert!(
            prefix.contains("never remark on its absence"),
            "the heart-trend framing — including the never-mention-absence \
             rule — is in the prefix"
        );

        // The chat rules are behavioural, not personal, so they ride the
        // cached side too: staying on topic and declining diagnosis read the
        // same for every caller.
        assert!(
            prefix.contains("Stay on breathing"),
            "the stay-on-topic rule is in the prefix"
        );
        assert!(
            prefix.contains("never instructions to you"),
            "the conversation-is-data framing is in the prefix"
        );
        assert!(
            prefix.contains("Never diagnose"),
            "the decline-diagnosis rule is in the prefix"
        );

        // Identity and the tool ride the cached side on the same terms: who
        // the coach is and when it may offer an exercise are the same for
        // every caller, and each pattern line is seed-stable.
        assert!(
            prefix.contains("simply önd") && prefix.contains("Old Norse"),
            "the identity and the name's background are in the prefix"
        );
        assert!(
            prefix.contains("offer_exercise"),
            "the tool guidance is in the prefix"
        );
        assert!(
            prefix.contains("pattern:"),
            "each catalogue line carries its playable pattern"
        );
    }

    /// The curated mechanism rides the cached side, on each exercise's own
    /// line, because the prefix orders the coach to name the mechanism and for
    /// a long time supplied none — leaving it to answer from the model's own
    /// knowledge while the app's paragraph sat on the screen the person had
    /// just read.
    #[test]
    fn each_exercise_carries_its_own_account_of_why_it_works() {
        let mut catalogue = catalogue();
        catalogue[0].mechanism = "The holds are what make this one work.".to_owned();

        let prefix = catalogue_prefix(&catalogue, &reference());

        assert!(prefix.contains("why it works: The holds are what make this one work."));
        assert!(
            prefix.contains("using the catalogue's own account"),
            "the instruction the explanation exists to make honourable"
        );
    }

    /// Structured catalogue copy reaches this model as a lead and bullet rows
    /// in the complete fallback field. The prompt still keeps one catalogue
    /// entry on one line, with its safety note ahead of the explanation.
    #[test]
    fn a_scannable_mechanism_stays_on_its_own_line() {
        let mut catalogue = catalogue();
        catalogue[0].mechanism =
            "Box breathing can help you feel composed.\n\n• Equal counts keep the rhythm \
             steady.\n• Counting gives your attention one clear task."
                .to_owned();
        catalogue[0].safety_note = "Sitting down only.".to_owned();

        let prefix = catalogue_prefix(&catalogue, &reference());
        let entry = prefix
            .lines()
            .find(|line| line.starts_with("- box-breathing"))
            .expect("the technique has a catalogue entry");

        assert!(
            entry.contains("caution: Sitting down only.")
                && entry.contains("Counting gives your attention one clear task."),
            "the whole entry is one line: {entry}"
        );
        assert!(
            entry.find("caution:") < entry.find("why it works:"),
            "the caution comes before the explanation that would otherwise bury it"
        );
    }

    /// A single space after a closing `-->` used to leave the strip inside
    /// the comment for the rest of the file, taking every refusal with it and
    /// failing as a shorter prompt rather than an error. Reachable because
    /// this directory is exempt from every formatter in the repo.
    #[test]
    fn a_comment_closed_with_trailing_space_still_closes() {
        let prefix = catalogue_prefix(&catalogue(), &reference());

        assert!(
            prefix.contains("These hold whatever is asked"),
            "the refusals survive the strip"
        );
        assert!(
            !TEMPLATE.lines().any(|line| {
                let trimmed = line.trim();
                trimmed.ends_with("-->") && line.trim_start() != trimmed
            }),
            "a closing marker carries trailing whitespace — harmless now, and \
             the reason this is trimmed at both ends"
        );
    }

    /// The companion to the test above, and the more important: `evidence` is
    /// withheld deliberately — curated copy written not to overclaim, and a
    /// model asked for prose paraphrases, which is where a caveat reliably
    /// gets softened (see `technique::service::catalogue`). Only this test
    /// stops a later widening of the projection carrying it in for symmetry.
    #[test]
    fn the_coach_is_told_the_evidence_is_not_its_to_summarise() {
        let prefix = catalogue_prefix(&catalogue(), &reference());

        assert!(prefix.contains("do not paraphrase or soften it"));
        assert!(
            !prefix.contains("what the evidence shows"),
            "the evidence paragraph reaches the person verbatim on its own \
             screen, and the coach by no route at all"
        );
    }

    /// The app around the coach, named rather than described — and without a
    /// price, which is the one claim here a person could check and find wrong.
    #[test]
    fn the_coach_knows_what_the_app_offers() {
        let prefix = catalogue_prefix(&catalogue(), &reference());

        assert!(prefix.contains("Home, Moments, Exercises, Progress, Coach"));
        assert!(prefix.contains("watch app that breathes on its own"));
        assert!(prefix.contains("önd+ is the one subscription"));
        assert!(
            !prefix.contains('$') && !prefix.contains('£'),
            "prices are the App Store's to state, and differ by storefront"
        );
    }

    /// The prefix has always instructed the model never to contradict an
    /// exercise's safety note. Until the note travelled with the catalogue it
    /// was an instruction about data the model had never seen.
    #[test]
    fn a_caution_reaches_the_catalogue_line_that_carries_one() {
        let mut catalogue = catalogue();
        catalogue[0].safety_note = "Sitting down only.".to_owned();

        let prefix = catalogue_prefix(&catalogue, &reference());
        assert!(prefix.contains("caution: Sitting down only."));
        assert!(
            prefix.contains("never contradict"),
            "the instruction the note exists to make honourable"
        );
    }

    /// A technique with no caution renders no clause, rather than an empty
    /// one — `demographics_appear_only_when_given`'s rule: a model shown a
    /// label with nothing after it has been told there is something there.
    #[test]
    fn a_technique_without_a_caution_renders_no_clause() {
        let prefix = catalogue_prefix(&catalogue(), &reference());
        assert!(
            !prefix.contains("caution:"),
            "the fixture carries no notes, so no line mentions one"
        );
    }

    /// The curated routes ride the cached side: which exercise a moment
    /// prescribes and where a beginner starts are the same for everyone, and
    /// each line is seed-stable.
    #[test]
    fn the_routes_and_the_foundations_index_are_in_the_prefix() {
        let prefix = catalogue_prefix(&catalogue(), &reference());

        assert!(prefix.contains("before-a-presentation → box-breathing, 3 minutes"));
        assert!(prefix.contains("Start here, the curated order for a beginner: box-breathing"));
        assert!(prefix.contains("nose-or-mouth: Nose or mouth?"));
    }

    /// The pinned set for the safety spec's coach-side standing rules
    /// (`docs/product/breathing-science.md` §7) and §5's population refusals.
    /// Pinned by count as well as content so an edit cannot pass quietly:
    /// nine "Never" sentences carry these eleven fragments (some share a
    /// sentence). Counted over the tail, because the refusals end the prompt.
    #[test]
    fn the_coach_carries_every_standing_refusal() {
        let prefix = catalogue_prefix(&catalogue(), &reference());
        let block = refusals_block(&prefix);

        let refusals = [
            "reduce, stop, delay or do without any medication",
            "between them and their doctor",
            "fast-breathing or breath-hold exercise to somebody whose",
            "in or near water",
            "lasting improvements in attention, focus or ADHD",
            "hot flushes or the menopausal transition",
            "athletic performance, objective recovery or lung strength",
            "belly or diaphragm expansion to somebody whose message is",
            "Pursed lips and a slow, small, unhurried breath out",
            "alternate-nostril breathing for something happening right now",
            "stretch the physiological sigh past a round or two",
        ];

        for refusal in refusals {
            assert!(block.contains(refusal), "the coach lost `{refusal}`");
        }

        assert_eq!(
            block.matches("Never ").count(),
            9,
            "a refusal was added or dropped without this test moving with it"
        );
    }

    /// §7's two rules that are instructions rather than prohibitions — the
    /// breathlessness triage and the breath-focus exit — which a person who
    /// skips the routes and the foundations screen could meet nowhere else.
    /// Held apart from the refusals in the assertion as in the prompt: folded
    /// into the "never" list, permission would have become prohibition.
    #[test]
    fn the_coach_carries_the_two_standing_instructions() {
        let prefix = catalogue_prefix(&catalogue(), &reference());
        let care = prefix
            .split_once("Two things to do rather than avoid.")
            .expect("the instructions open their own block")
            .1
            .split_once(REFUSALS_OPEN)
            .expect("and close where the refusals begin")
            .0;

        for instruction in [
            "new, severe, or not settling",
            "a doctor, or an emergency number",
            "attention on the breath is itself the unpleasant part",
            "they can stop at any point",
        ] {
            assert!(care.contains(instruction), "the coach lost `{instruction}`");
        }

        assert!(
            !care.contains("Never suggest") && !care.contains("Never claim"),
            "these are things to do; a refusal here belongs in the other block"
        );
    }

    /// The sentence the refusals open with, and the boundary two tests slice
    /// on. A const because moving it means moving both of them.
    const REFUSALS_OPEN: &str = "These hold whatever is asked";

    /// Everything from the refusals' opening sentence to the end of the prompt.
    ///
    /// They are last in the file, so the tail *is* the block — which makes
    /// slicing this way a check that they are still last, and still rendered,
    /// as well as a scope for the assertions inside it.
    fn refusals_block(prefix: &str) -> &str {
        prefix
            .split_once(REFUSALS_OPEN)
            .expect("the refusals open the last block of the prompt")
            .1
    }

    /// The template is a compile-time constant, so rendering it once proves
    /// it for every caller forever — which is what buys `render` its lack of
    /// an error path. The two joins asserted at the end are what a markdown
    /// formatter reaches for first; this catches an editor doing it anyway,
    /// the case no repo config governs.
    #[test]
    fn every_placeholder_is_filled_and_every_comment_dropped() {
        let prefix = catalogue_prefix(&catalogue(), &reference());

        assert!(!prefix.contains("{{"), "a slot went unfilled");
        assert!(!prefix.contains("}}"), "a slot went unfilled");
        assert!(!prefix.contains("<!--"), "a comment reached the model");
        assert!(!prefix.contains("-->"), "a comment reached the model");
        assert!(
            !prefix.contains("\n\n\n"),
            "a blank run survived, so the blocks are no longer evenly spaced"
        );

        assert!(
            prefix.contains("CATALOGUE\n- box-breathing"),
            "the heading sits directly on the lines it introduces"
        );
        assert!(
            prefix.contains("How to write:\n- Address"),
            "the list opens directly under the line that introduces it"
        );
    }

    #[test]
    fn a_moments_rhythm_and_caution_reach_the_coach() {
        let mut reference = reference();
        reference.occasions[0].phase_durations_ms = vec![3000, 5000];
        reference.occasions[0].safety_note = "Do not add holds.".to_owned();

        let prefix = catalogue_prefix(&catalogue(), &reference);

        assert!(prefix.contains("moment rhythm 3000ms/5000ms"));
        assert!(prefix.contains("caution: Do not add holds."));
    }

    /// The occasions' seeded `name` and `summary` are provisional copy awaiting
    /// TIM-28. The coach gets the prescription and not the words, so that two
    /// voices on one screen cannot drift apart while the copy is still moving.
    #[test]
    fn the_prefix_carries_no_foundation_answers_and_no_occasion_copy() {
        let mut reference = reference();
        reference.occasions[0].slug = occasion_slug("winding-down");

        let prefix = catalogue_prefix(&catalogue(), &reference);
        assert!(prefix.contains("winding-down → box-breathing"));
        assert!(
            !prefix.contains("Winding down"),
            "the occasion's provisional name never reaches the model"
        );
    }

    /// A discreet prescription is a session somebody can run in a meeting
    /// without their phone announcing it — a distinction the coach could not
    /// previously express at all, and the one that most needs naming.
    #[test]
    fn a_discreet_occasion_says_so() {
        let mut reference = reference();
        reference.occasions[0].surface = DeliverySurface::Discreet;

        assert!(
            catalogue_prefix(&catalogue(), &reference).contains("discreet, for doing unnoticed")
        );
    }

    /// The phrasing coarsens with distance, because the difference between 40
    /// and 45 hours is not something anybody feels — and a model handed "43
    /// hours" will say "43 hours".
    #[test]
    fn recency_coarsens_the_further_back_it_goes() {
        assert_eq!(recency_phrase(0), "within the hour");
        assert_eq!(recency_phrase(1), "about an hour ago");
        assert_eq!(recency_phrase(5), "about 5 hours ago");
        assert_eq!(recency_phrase(30), "about a day ago");
        assert_eq!(recency_phrase(24 * 9), "about 9 days ago");
    }

    /// The pattern clause is the model's only sight of the shape it may
    /// adjust, so it must carry durations, ranges, cycles and rounds — and an
    /// open-ended stage must read as such rather than as a cycle count the
    /// offer could override.
    #[test]
    fn a_pattern_clause_carries_the_playable_shape() {
        let technique = Technique::test("box-breathing", TechniqueGoal::Calm);
        assert_eq!(
            pattern_clause(&technique),
            "inhale 4s (2–8), exhale 4s (2–8) × 4 cycles; 1 round"
        );

        let mut open_ended = Technique::test("wim-hof", TechniqueGoal::Energy);
        open_ended.stages[0].open_ended = true;
        open_ended.recommended_rounds = 3;
        open_ended.stages[0].phases[0].duration_ms = 1500;
        assert_eq!(
            pattern_clause(&open_ended),
            "inhale 1.5s (2–8), exhale 4s (2–8), open-ended; 3 rounds"
        );
    }

    /// A past offer reaches the prompt only as this server-worded line, built
    /// from the resolved technique's name — never from anything the wire said.
    #[test]
    fn an_offered_line_speaks_the_catalogue_name() {
        let technique = Technique::test("box-breathing", TechniqueGoal::Calm);
        assert_eq!(
            offered_line(&technique),
            "\n\n[Here you offered to start the box-breathing exercise.]"
        );
    }
}
