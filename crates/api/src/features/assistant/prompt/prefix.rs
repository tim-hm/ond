//! The half of the prompt every caller shares, and the only half worth caching.
//!
//! Built once per request from data that changes only when the seed does, so
//! the catalogue, the routes and the measurement bands cannot drift from what
//! the app itself shows. What is written out rather than derived — the persona,
//! the how-to-write rules, the card etiquette, the refusals — is here because
//! nothing in the database holds it, and each such block carries the reason it
//! is worded the way it is.

use std::fmt::Write as _;

use super::super::types::{
    BOLT_BAND_BUILDING, BOLT_BAND_SOLID, BOLT_BAND_STRONG, BOLT_BAND_TARGET,
    RESTING_RATE_BAND_BRISK, RESTING_RATE_BAND_SLOW, RESTING_RATE_BAND_TYPICAL, goal_phrase,
};
use crate::features::technique::types::{
    DeliverySurface, PhaseKind, PlayableStage, Reference, Technique,
};

/// The instructions and the catalogue: the same bytes on every call.
///
/// Everything here is stable per deployment, which is what makes it worth
/// caching. Note what is absent — no profile, no practice, no name, no note.
/// Adding one personal detail to this string would make the prefix per-caller
/// and quietly turn a cache read back into a full-price write. The measurement
/// briefings after the catalogue stay on this side of the boundary for the same
/// reason the catalogue does: they are how to *read* a breathing rate and a
/// pause — which of the two carries the evidence, and the bands each is read
/// against — never anybody's own figures.
pub fn catalogue_prefix(catalogue: &[Technique], reference: &Reference) -> String {
    let typical_top = RESTING_RATE_BAND_BRISK - 1;
    let aiming_at = RESTING_RATE_BAND_SLOW - 1;

    render(
        TEMPLATE,
        &[
            ("catalogue", &catalogue_lines(catalogue)),
            ("protocols", &reference_lines(reference)),
            ("resting_typical", &RESTING_RATE_BAND_TYPICAL.to_string()),
            ("resting_typical_top", &typical_top.to_string()),
            ("resting_aim", &aiming_at.to_string()),
            ("bolt_building", &BOLT_BAND_BUILDING.to_string()),
            ("bolt_solid", &BOLT_BAND_SOLID.to_string()),
            ("bolt_strong", &BOLT_BAND_STRONG.to_string()),
            ("bolt_target", &BOLT_BAND_TARGET.to_string()),
        ],
    )
}

/// The prompt's prose, verbatim and compiled in.
///
/// A file rather than a string literal because it is edited as writing and read
/// as writing: the escaping a multi-line Rust literal needs made a paragraph
/// break something you had to spell, and the assembled prompt could only be
/// seen by running the code. Compiled in with `include_str!`, so there is
/// nothing to deploy and nothing to read at runtime.
const TEMPLATE: &str = include_str!("copy/prefix.md");

/// Fills a template's `{{ name }}` slots, having first dropped its comments.
///
/// No error path and no escaping. Both are affordable because [`TEMPLATE`] is a
/// compile-time constant: an unfilled slot or a stray comment marker is the
/// same on every run, so a test that renders once has proved it for every
/// caller forever — which is what
/// `every_placeholder_is_filled_and_every_comment_dropped` is. A templating
/// crate would buy runtime errors for a string that cannot vary at runtime.
///
/// Comments are dropped by whole lines rather than by matching across them, so
/// a `<!--` inside a paragraph is prose and only a line that opens with one is
/// a comment. That is the stricter reading, and it keeps the paragraph spacing
/// of the output a thing you can see in the file.
///
/// Removing a comment leaves the blank lines that surrounded it, which is why
/// runs of them collapse to one afterwards: whether the author put a blank line
/// under a `-->` is then not something the prompt can be changed by. It is the
/// only whitespace liberty taken here, and it exists because a markdown
/// formatter's first instinct is to add exactly that line — `vite.config.ts`
/// keeps this directory away from ours, and this keeps an editor's from
/// mattering either.
fn render(template: &str, slots: &[(&str, &str)]) -> String {
    let mut out = String::with_capacity(template.len());
    let mut in_comment = false;

    for line in template.lines() {
        let trimmed = line.trim_start();
        if in_comment {
            in_comment = !trimmed.ends_with("-->");
            continue;
        }
        if trimmed.starts_with("<!--") {
            in_comment = !trimmed.ends_with("-->");
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }

    while out.contains("\n\n\n") {
        out = out.replace("\n\n\n", "\n\n");
    }

    for (name, value) in slots {
        out = out.replace(&format!("{{{{ {name} }}}}"), value);
    }

    out.trim_start().to_owned()
}

/// Every technique as one line each, without the trailing newline the template
/// already provides around the slot.
fn catalogue_lines(catalogue: &[Technique]) -> String {
    let mut lines = String::new();

    for technique in catalogue {
        // `write!` into a String is infallible; the `Write` import is what makes
        // the macro usable at all.
        let _ = writeln!(
            lines,
            "- {} | helps them {} | {} | pattern: {} | why it works: {}{}",
            technique.slug,
            goal_phrase(technique.goal),
            technique.summary,
            pattern_clause(technique),
            technique.mechanism,
            caution_clause(technique)
        );
    }

    lines.truncate(lines.trim_end().len());
    lines
}

/// One technique's playable shape as a clause of its catalogue line: each
/// phase with its duration and allowed range in seconds, each stage's cycle
/// count, and the recommended rounds.
///
/// This is what makes the offer's parameters *possible*: the tool's ranges
/// mean nothing to a model that was never shown the shape it is adjusting.
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

/// The app's own curated routes, as blocks of the cached prefix.
///
/// Mappings rather than copy throughout, and the reason is worth stating once:
/// the coach and the screens have to agree. Somebody who tapped "before a
/// presentation" and then asked about it should not be told something different,
/// and a beginner asking where to start should get the order the app already
/// curates rather than one the model invented. What the coach must *not* get is
/// the seeded wording, which is provisional — see
/// [`Occasion`](crate::features::technique::types::Occasion).
///
/// The foundations are an index: the questions, no answers. The model then
/// knows the app holds a position on nose-versus-mouth and hold length and can
/// stay in that lane, for a hundred tokens rather than fourteen hundred.
pub(super) fn reference_lines(reference: &Reference) -> String {
    let mut lines = String::new();

    if !reference.occasions.is_empty() {
        lines.push_str(
            "PROTOCOLS (the app's own entry points, on their own tab — a \
             person may have arrived from one of these)\n",
        );
        for occasion in &reference.occasions {
            let rhythm = if occasion.phase_durations_ms.is_empty() {
                String::new()
            } else {
                format!(
                    ", protocol rhythm {}",
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

    // The template owns the blank lines around this slot, so the block hands
    // back its own lines and nothing else. Every section above is conditional,
    // and each opens with the separator its predecessor did not write.
    lines.truncate(lines.trim_end().len());
    lines
}

/// Whole hours since the last session, in the coarse words a coach would use.
///
/// Deliberately vaguer the further back it goes: the difference between 40 and
/// 45 hours is not something anybody feels, and a model handed "43 hours" will
/// say "43 hours". Days rather than a date, because a date needs a time zone and
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
/// nothing at all for the ten that carry none.
///
/// Absence is the absence of a clause, never an empty field — the demographics
/// lines' rule, for the demographics lines' reason: a model shown
/// `caution: ` with nothing after it has been told there is a caution.
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
/// exercise offer.
///
/// Built from the *resolved* technique's name and never from the wire slug:
/// the wire value is client free text, and this line is the only shape in
/// which a past offer ever reaches the prompt.
pub fn offered_line(technique: &Technique) -> String {
    format!(
        "\n\n[Here you offered to start the {} exercise.]",
        technique.name
    )
}
