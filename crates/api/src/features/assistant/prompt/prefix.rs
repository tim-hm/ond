//! The half of the prompt every caller shares, and the only half worth
//! caching. Built from data that changes only when the seed does, so the
//! catalogue, routes and measurement bands cannot drift from what the app
//! shows. What is written out rather than derived — persona, how-to-write
//! rules, card etiquette, refusals — is here because no database holds it.

use std::fmt::Write as _;
use std::sync::LazyLock;

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

/// The prompt's prose, verbatim and compiled in. A file rather than a string
/// literal because it is edited and read as writing: a multi-line literal's
/// escaping made a paragraph break something you had to spell. `include_str!`
/// means there is nothing to deploy and nothing to read at runtime.
pub(super) const TEMPLATE: &str = include_str!("copy/prefix.md");

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
pub(super) fn pattern_clause(technique: &Technique) -> String {
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
