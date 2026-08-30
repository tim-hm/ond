//! The answer when there is no model — offline-first, applied on the server.
//! The promise the app makes without signal must survive the model being down,
//! over quota, breaker-tripped, or unbought, so these rules build a real
//! answer from catalogue, profile, and practice, flagged `FALLBACK` or
//! `SUBSCRIPTION_REQUIRED` — the ranking is the person's own goal ordering.

use super::types::{RECOMMENDATION_COUNT, Recommendation, goal_phrase};
use crate::features::journey::sessions::types::PracticeSnapshot;
use crate::features::profile::types::ProfileSnapshot;
use crate::features::technique::types::{Technique, TechniqueGoal, resolve};

/// Techniques to try, ranked by the goals the person picked: first goal first,
/// catalogue order within each, then the rest in catalogue order, so the list
/// is always full. Catalogue order is curated for newcomers, which makes it
/// the right tiebreak. The practice snapshot buys one history-aware judgement:
/// an unpractised first goal is named in the lead reason, not repeated back.
pub fn recommendations(
    catalogue: &[Technique],
    profile: &ProfileSnapshot,
    practice: &PracticeSnapshot,
) -> Vec<Recommendation> {
    let mut ranked: Vec<&Technique> = catalogue.iter().collect();

    // A *stable* sort is what expresses the whole rule: techniques serving an
    // earlier goal come first, catalogue order survives within each goal, and
    // everything the person did not ask for keeps its curated order at the end.
    ranked.sort_by_key(|technique| {
        profile
            .goals
            .iter()
            .position(|goal| *goal == technique.goal)
            .unwrap_or(usize::MAX)
    });

    let mut list: Vec<Recommendation> = ranked
        .into_iter()
        .take(RECOMMENDATION_COUNT)
        .map(|technique| Recommendation {
            technique_slug: technique.slug.clone(),
            reason: reason(technique, profile),
        })
        .collect();

    if let (Some(lead), Some((stated, practised))) =
        (list.first_mut(), goal_gap(catalogue, profile, practice))
    {
        lead.reason = format!(
            "You've been practising to {}, but you said you want to {} — start here.",
            goal_phrase(practised),
            goal_phrase(stated)
        );
    }

    list
}

/// The one judgement that watches the person's data: their first goal has had
/// strictly zero recent minutes while resolvable practice went elsewhere.
/// Returns `(stated, practised)`, or `None` in every other shape. Reads only
/// the snapshot's named techniques, so a goal practised entirely in the
/// truncated tail can look neglected — the tail is one-offs by construction.
fn goal_gap(
    catalogue: &[Technique],
    profile: &ProfileSnapshot,
    practice: &PracticeSnapshot,
) -> Option<(TechniqueGoal, TechniqueGoal)> {
    let stated = *profile.goals.first()?;
    let goal_of = |slug: &str| resolve(catalogue, slug).map(|technique| technique.goal);

    if practice
        .by_technique
        .iter()
        .any(|entry| entry.minutes > 0 && goal_of(entry.technique_slug.as_str()) == Some(stated))
    {
        return None;
    }

    // Busiest first, so the goal named is the one their sessions actually went
    // to.
    let practised = practice
        .by_technique
        .iter()
        .filter(|entry| entry.minutes > 0)
        .find_map(|entry| goal_of(entry.technique_slug.as_str()).filter(|goal| *goal != stated))?;

    Some((stated, practised))
}

/// Why this technique, in one sentence: one shape for a technique serving a
/// named goal, one for a good place to start. Neither claims to be more
/// personalised than the profile says — the client is told this came from the
/// rules, and copy that oversold itself would make that flag a lie.
fn reason(technique: &Technique, profile: &ProfileSnapshot) -> String {
    if profile.goals.contains(&technique.goal) {
        format!(
            "You said you want to {} — this is one of the ways in.",
            goal_phrase(technique.goal)
        )
    } else {
        format!(
            "A steady place to start, and it will help you {}.",
            goal_phrase(technique.goal)
        )
    }
}

/// The reply when a conversation cannot reach the model, for a caller whose
/// tier does buy one. Fixed text: the rules can rank exercises but cannot
/// chat. Every clause is about a wait that ends — quota resets, breaker
/// closes, provider returns. It must never answer a tier that buys no call at
/// all; that is [`CHAT_SUBSCRIPTION_REPLY`], the whole reason for the pair.
pub const CHAT_REPLY: &str = "The coach can't reply just now. Every exercise \
                              still works without it — pick one, practise, \
                              and ask again later.";

/// The reply when the caller's tier buys no model call at all — the one string
/// the client cannot infer: told "ask again later", somebody on Free would ask
/// again and conclude the app is broken. Points at the plan, not a purchase:
/// the iOS caller who reaches this is a paid subscriber whose receipt has not
/// landed (`entitlement sync deferred`); `StoreKit` 2 re-submits it by itself.
pub const CHAT_SUBSCRIPTION_REPLY: &str = "Asking the coach is part of önd+. Every exercise still works without \
     it — Settings shows what önd+ adds, and which plan this device is on.";

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::journey::sessions::types::{PRACTICE_WINDOW_DAYS, TechniquePractice};
    use crate::features::technique::types::TechniqueGoal;
    use crate::features::technique::types::TechniqueSlug;

    fn catalogue() -> Vec<Technique> {
        vec![
            Technique::test("box-breathing", TechniqueGoal::Calm),
            Technique::test("four-seven-eight", TechniqueGoal::Sleep),
            Technique::test("coffee-breath", TechniqueGoal::Energy),
        ]
    }

    fn profile(goals: Vec<TechniqueGoal>) -> ProfileSnapshot {
        ProfileSnapshot {
            goals,
            experience_level: None,
            intent_note: String::new(),
            birth_year_band: None,
            gender: None,
            given_name: None,
        }
    }

    fn no_practice() -> PracticeSnapshot {
        PracticeSnapshot {
            window_days: u32::from(PRACTICE_WINDOW_DAYS),
            sessions: 0,
            minutes: 0,
            active_days: 0,
            by_technique: vec![],
            bolt: None,
            resting_rate: None,
            lifetime: None,
            hours_since_last: None,
            streak: None,
        }
    }

    fn practice_of(slug: &str, sessions: u32, minutes: u32) -> PracticeSnapshot {
        PracticeSnapshot {
            sessions,
            minutes,
            active_days: 1,
            by_technique: vec![TechniquePractice {
                technique_slug: TechniqueSlug::parse("slug", slug).expect("a fixture slug"),
                sessions,
                minutes,
            }],
            ..no_practice()
        }
    }

    /// The history-aware sentence: sleep is the stated goal, calm is where the
    /// minutes went, so the lead reason names the gap instead of repeating the
    /// goal back — and the lead technique still serves the stated goal.
    #[test]
    fn an_unpractised_first_goal_gets_a_corrective_lead() {
        let list = recommendations(
            &catalogue(),
            &profile(vec![TechniqueGoal::Sleep]),
            &practice_of("box-breathing", 5, 12),
        );

        assert_eq!(list[0].technique_slug.as_str(), "four-seven-eight");
        assert_eq!(
            list[0].reason,
            "You've been practising to settle in the moment, but you said you want to \
             wind down towards sleep — start here."
        );
        // Only the lead is corrective; the rest keep the ordinary shapes.
        assert!(list[1].reason.ends_with('.'));
        assert!(!list[1].reason.contains("start here"));
    }

    /// No practice at all means nothing to contrast, so nobody's first day
    /// opens with a correction.
    #[test]
    fn no_practice_means_no_correction() {
        let list = recommendations(
            &catalogue(),
            &profile(vec![TechniqueGoal::Sleep]),
            &no_practice(),
        );

        assert_eq!(
            list[0].reason,
            "You said you want to wind down towards sleep — this is one of the ways in."
        );
    }

    /// A first goal with any recent minutes is being practised, and correcting
    /// somebody who is doing the thing would make the copy a nag.
    #[test]
    fn a_practised_first_goal_is_left_alone() {
        let list = recommendations(
            &catalogue(),
            &profile(vec![TechniqueGoal::Sleep]),
            &practice_of("four-seven-eight", 2, 6),
        );

        assert!(!list[0].reason.contains("start here"));
    }

    /// A slug the catalogue cannot resolve proves nothing about their goals,
    /// so it neither triggers a correction nor is quoted anywhere.
    #[test]
    fn unresolvable_practice_does_not_correct() {
        let list = recommendations(
            &catalogue(),
            &profile(vec![TechniqueGoal::Sleep]),
            &practice_of("moon-breathing", 5, 12),
        );

        assert!(!list[0].reason.contains("start here"));
    }
}
