//! The curated catalogue itself — the nine techniques, the foundation topics,
//! and the routes into them, as data.
//!
//! Apart from `super` because the two change for different reasons: this file is
//! edited when a technique's phrasing or timing changes, and `seed` when the way
//! reference data reaches the database does.
//!
//! A child of `seed` rather than a sibling, which is what keeps the vocabulary
//! private. The seed structs and the `const fn` builders that make a hold unable
//! to carry a passage stay unreachable from the rest of the crate, so
//! `PhaseSeed`'s "the four constructors below are the only way to build one of
//! these" remains true rather than becoming a claim about a `pub(crate)` type
//! anything could construct.

use super::{
    DeliverySurface, FoundationSeed, OccasionSeed, Passage, ProgressionStepSeed, TechniqueGoal,
    TechniqueSeed, exhale, hold_in, hold_out, inhale, open_ended_stage, stage,
};

/// Array order is presentation order — `sort_order` is the index, so reordering
/// this list is the only edit needed to reorder the catalogue. Techniques are
/// grouped by goal in the order a newcomer meets them: calm first, the fast and
/// contraindicated ones well down the list.
pub(super) const TECHNIQUES: &[TechniqueSeed] = &[
    TechniqueSeed {
        slug: "box-breathing",
        name: "Box Breathing",
        summary: "Four equal counts — in, hold, out, hold. The most forgiving place to start, \
                  and the one to reach for before something stressful rather than during it.",
        safety_note: "",
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 8000)),
                hold_in(4000, (2000, 8000)),
                exhale(Passage::Nose, 4000, (3000, 8000)),
                hold_out(4000, (2000, 8000)),
            ],
            // Eight sixteen-second cycles — a little over two minutes, the
            // length a first session should be to feel worth doing and still
            // fit in a gap between meetings.
            8,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "coherent-breathing",
        name: "Coherent Breathing",
        summary: "One long breath in, one just as long out — about five and a half breaths a \
                  minute. No holds and nothing to count: at this pace heart rate and breath fall \
                  into step on their own, which is the whole of the exercise.",
        safety_note: "",
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            // The resonance range sits near six breaths a minute for most
            // people and is worth exploring by feel — hence a dial that reaches
            // four seconds (7.5/min) and seven (4.3/min) either side.
            &[
                inhale(Passage::Nose, 5500, (4000, 7000)),
                exhale(Passage::Nose, 5500, (4000, 7000)),
            ],
            // Just under five minutes. Resonance work is studied in bouts of
            // five to ten, and five is the one people actually come back to.
            27,
        )],
        recommended_rounds: 1,
        requires_subscription: true,
    },
    TechniqueSeed {
        slug: "four-seven-eight",
        name: "4-7-8 Breathing",
        summary: "Inhale for four, hold for seven, exhale for eight. The long exhale is doing the \
                  work; if the hold feels strained, shorten all three and keep the ratio.",
        safety_note: "",
        goal: TechniqueGoal::Sleep,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 6000)),
                hold_in(7000, (4000, 10000)),
                exhale(Passage::Nose, 8000, (6000, 12000)),
            ],
            // Four is the count the technique is taught with, and the count its
            // originator caps beginners at.
            4,
        )],
        recommended_rounds: 1,
        requires_subscription: true,
    },
    TechniqueSeed {
        slug: "extended-exhale",
        name: "Extended Exhale",
        summary: "In for four, out for six. The same lever 4-7-8 pulls — an out-breath longer \
                  than the in-breath — with no hold to strain against. Stretch the exhale towards \
                  eight when six stops feeling like enough.",
        safety_note: "",
        goal: TechniqueGoal::Sleep,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 5000)),
                // Six to eight is the range the evidence is gathered at, and the
                // one the summary invites people to walk up.
                exhale(Passage::Nose, 6000, (6000, 8000)),
            ],
            // Twelve ten-second cycles: two minutes, long enough for the shift
            // to be noticeable and short enough to do in bed without deciding to.
            12,
        )],
        recommended_rounds: 1,
        requires_subscription: true,
    },
    TechniqueSeed {
        slug: "physiological-sigh",
        name: "Physiological Sigh",
        summary: "A full inhale, a second short sip of air on top, then a long slow exhale. \
                  One or two rounds is the whole exercise — it works in seconds, not minutes.",
        safety_note: "",
        goal: TechniqueGoal::Reset,
        stages: &[stage(
            // Two consecutive INHALE phases, deliberately. The second sip
            // re-inflates collapsed alveoli, and it is a distinct beat the
            // client must cue separately — merging them into one long inhale
            // loses the technique.
            &[
                inhale(Passage::Nose, 1500, (1000, 2500)),
                inhale(Passage::Nose, 700, (500, 1200)),
                exhale(Passage::Mouth, 5000, (4000, 8000)),
            ],
            // The summary promises "one or two rounds"; three is the generous
            // end of that, and the technique loses its point when stretched
            // into a session.
            3,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "bellows-breath",
        name: "Bellows Breath",
        summary: "Rapid, forceful, equal inhales and exhales through the nose. A short bout is \
                  the whole dose — this one raises alertness in under a minute and has nothing \
                  more to give after that.",
        safety_note: "Sitting down only. Stop at the first sign of lightheadedness. Never in \
                      water, never while driving.",
        goal: TechniqueGoal::Energy,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 1000, (700, 1500)),
                exhale(Passage::Nose, 1000, (700, 1500)),
            ],
            // Twenty two-second breaths is forty seconds — a short bout, which
            // is the only kind this technique should be practised in.
            20,
        )],
        recommended_rounds: 1,
        requires_subscription: true,
    },
    TechniqueSeed {
        slug: "wim-hof-rounds",
        name: "Wim Hof-style Rounds",
        summary: "Thirty full, unforced breaths and one last deep one, then let the air go and \
                  wait — the hold after them is the point, and it lasts as long as it lasts. One \
                  deep breath in, held for fifteen seconds, closes each round. Popular, well \
                  described by people who practise it, and thinner on trial evidence than its \
                  reputation suggests.",
        safety_note: "Sitting or lying down, always. Never in water, never in the bath, never \
                      driving or standing — fast breathing can make you faint with no warning. \
                      Tingling in the hands and face is ordinary; dizziness means stop. Never \
                      push a hold to the limit: this app does not measure one.",
        goal: TechniqueGoal::Energy,
        stages: &[
            stage(
                &[
                    inhale(Passage::Nose, 1500, (1000, 2500)),
                    exhale(Passage::Nose, 1500, (1000, 2500)),
                ],
                // Thirty is the count the protocol is described with, and the
                // bottom of the thirty-to-forty range people practise it at.
                30,
            ),
            // The last deep breath, in and out, which the thirty above do not
            // contain and which the catalogue used to leave to chance: the
            // session ran the thirtieth exhale straight into the retention, so
            // the hold started a breath before the person did. Slower than the
            // thirty because it fills the lungs rather than keeping their pace.
            stage(
                &[
                    inhale(Passage::Nose, 4000, (3000, 6000)),
                    exhale(Passage::Nose, 4000, (2000, 6000)),
                ],
                1,
            ),
            // The retention, held empty, as the published protocol describes
            // it: the breath above goes out, and nothing comes in until the
            // person decides it does.
            //
            // Alone in its stage because open-endedness is a property of the
            // stage rather than the phase — every phase inside one is a phase
            // the clock never ends, so a breath sharing it would wait for a tap
            // nothing asks for and draw as a hold nobody times.
            //
            // Its duration is what a settled practitioner tends to reach, shown
            // as a typical hold rather than a target — the range is a single
            // point because there is no dial here at all.
            open_ended_stage(&[hold_out(60000, (60000, 60000))]),
            stage(
                &[
                    inhale(Passage::Nose, 3000, (2000, 5000)),
                    hold_in(15000, (10000, 20000)),
                    exhale(Passage::Nose, 4000, (2000, 6000)),
                ],
                1,
            ),
        ],
        // Three rounds is the described protocol, and the count at which the
        // hold typically lengthens on its own — which is the reason to do more
        // than one.
        recommended_rounds: 3,
        requires_subscription: true,
    },
    TechniqueSeed {
        slug: "long-box-breathing",
        name: "Long Box Breathing",
        summary: "Box breathing with longer sides — six counts each, or eight once six feels \
                  easy. The hold is what makes it a focus exercise rather than a calming one: \
                  there is enough to keep track of that there is no room left to drift.",
        safety_note: "",
        goal: TechniqueGoal::Focus,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 6000, (4000, 10000)),
                hold_in(6000, (4000, 10000)),
                exhale(Passage::Nose, 6000, (4000, 10000)),
                hold_out(6000, (4000, 10000)),
            ],
            // Six twenty-four-second cycles: two and a half minutes, the same
            // dose as box breathing at a pace that asks more of you.
            6,
        )],
        recommended_rounds: 1,
        requires_subscription: true,
    },
    TechniqueSeed {
        slug: "alternate-nostril",
        name: "Alternate-Nostril Breathing",
        summary: "Thumb closes the right nostril, ring finger the left. In through the left, out \
                  through the right, in through the right, out through the left — that sequence \
                  is one cycle, and the four beats on screen are its four breaths in order. A \
                  traditional practice with modest trial support and an unmistakable knack for \
                  holding attention.",
        safety_note: "",
        goal: TechniqueGoal::Focus,
        stages: &[stage(
            &[
                inhale(Passage::LeftNostril, 4000, (3000, 6000)),
                exhale(Passage::RightNostril, 6000, (4000, 8000)),
                inhale(Passage::RightNostril, 4000, (3000, 6000)),
                exhale(Passage::LeftNostril, 6000, (4000, 8000)),
            ],
            // Nine twenty-second cycles — three minutes, thirty-six breaths,
            // and the point at which the switching stops needing thought.
            9,
        )],
        recommended_rounds: 1,
        requires_subscription: true,
    },
];

/// Array order is reading order, same as the catalogue. These are ordered the
/// way the questions occur to someone learning: why bother at all, what moves,
/// what it goes through, how slow to go, where to sit, what to do with your
/// eyes.
pub(super) const FOUNDATIONS: &[FoundationSeed] = &[
    FoundationSeed {
        slug: "why-it-works",
        question: "Why does this work at all?",
        answer: "Breathing is the one automatic thing you can take over whenever you like, and \
                 taking it over reaches further than the lungs. Your heart speeds up a little on \
                 every breath in and slows on every breath out, so a long exhale leans on the \
                 brake rather than the accelerator. That is the mechanism under every slow \
                 pattern here, and it is why the change arrives sooner than talking yourself \
                 down does — the body settles first and the thinking follows it.",
    },
    FoundationSeed {
        slug: "belly-or-chest",
        question: "Belly or chest?",
        answer: "Belly, if you can. Rest a hand just below your ribs and let the breath drop low \
                 enough that this hand moves before your chest does — that is the diaphragm \
                 doing the work, which makes each breath deeper for less effort. Chest \
                 breathing is not a mistake, only a shallower version of the same thing, though \
                 it is the hurried version your body already associates with stress. The belly \
                 comes with practice faster than you would expect.",
    },
    FoundationSeed {
        slug: "nose-or-mouth",
        question: "In through the nose?",
        answer: "Where you can. The nose filters, warms, and humidifies the air, and picks up \
                 nitric oxide from the sinuses on the way past, which helps the oxygen cross \
                 into your blood. It is also the narrower path, so it slows the breath down \
                 without you deciding to. It is genuinely hard at first if you are congested or \
                 used to breathing through your mouth — and it does get easier. Start with your \
                 mouth if you need to; the breathing still works while you are learning.",
    },
    FoundationSeed {
        slug: "how-to-exhale",
        question: "And out through what?",
        answer: "Nose or pursed lips, whichever you can keep going. Out through the nose stays \
                 slow by default. Pursed lips — the shape for cooling a spoonful of soup — give \
                 you something to push against, which makes a long exhale much easier to hold \
                 onto. The out-breath is where most of the settling happens, so its length \
                 matters more than anywhere else in the round: whatever keeps yours smooth and \
                 unhurried is the right answer.",
    },
    FoundationSeed {
        slug: "how-slow",
        question: "How slow should it be?",
        answer: "Slower than usual, and never so slow that you are straining for air. Somewhere \
                 around five or six breaths a minute your breathing, heart rhythm, and blood \
                 pressure fall into step with one another, and that is the pace most of the \
                 research keeps landing on. You do not have to find it yourself — the guided \
                 patterns are built around it. If one leaves you short of air, it is too slow \
                 for today: shorten it, and come back to it in a week.",
    },
    FoundationSeed {
        slug: "sitting-or-lying",
        question: "Sit or lie down?",
        answer: "Sit for anything alerting, lie down for anything meant to end in sleep. Upright \
                 with a tall, easy back and your feet on the floor keeps you from drifting off \
                 halfway; on your back the belly moves more freely and nothing has to hold you \
                 up. Fast-breathing exercises are seated or lying down every time, never in \
                 water and never while driving — that one is not a suggestion.",
    },
    FoundationSeed {
        slug: "eyes-open-or-closed",
        question: "Eyes open or closed?",
        answer: "Closed is usually simpler: less to look at, less to think about, and it is \
                 where the haptics earn their keep — the phone taps out the rhythm, so nothing \
                 needs the screen. If closing them makes you uneasy, leave them open and rest \
                 your gaze on something dull a metre or two ahead; a soft gaze works just as \
                 well, and it is the easier choice in public. Watching the animation is the \
                 third option, and it is the one that makes the counting effortless.",
    },
];

/// The occasion entries: why somebody opened the app, and where that routes.
///
/// **Provisional copy, awaiting Tim's pass.** TIM-28 owns the final words for
/// every `name` and `summary` here, and the working set itself is a draft — the
/// five moments below exist so TIM-19 and TIM-128 have something real to build
/// against. What is *not* provisional is the shape: an occasion resolves to a
/// technique that already exists, a goal it borrows, a surface, and a duration
/// (TIM-60, D1).
///
/// Array order is presentation order — `sort_order` is the index, as in
/// [`TECHNIQUES`].
///
/// Three of the five route to techniques behind Plus, which is a curation
/// question rather than a mechanism one: a route says which technique, and
/// `requires_subscription` on that technique still says what it costs. Worth
/// deciding in the copy pass whether the entries a person meets first should
/// be ones they can breathe.
///
/// Two entries share a technique, a goal and a duration, and differ only in
/// their surface. That pair is the reason the surface is on the prescription at
/// all: sitting through a difficult meeting and recovering from one want the
/// same breathing and cannot want the same screen. Changing either dose is a
/// copy decision; collapsing the pair would take the mechanism out.
pub(super) const OCCASIONS: &[OccasionSeed] = &[
    OccasionSeed {
        slug: "before-a-presentation",
        name: "Before a presentation",
        summary: "Steady the nerves in the few minutes before you walk in.",
        technique_slug: "box-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        // Three minutes: long enough to land, short enough to still be doing it
        // in a corridor with somebody waiting.
        duration_ms: 180_000,
    },
    OccasionSeed {
        slug: "after-a-hard-meeting",
        name: "After a hard meeting",
        summary: "Come down from it before the next thing starts.",
        technique_slug: "coherent-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "through-this-meeting",
        name: "Through this meeting",
        summary: "Keep the rhythm going while somebody else is talking — nothing on screen, \
                  nothing to hear.",
        technique_slug: "coherent-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::Discreet,
        // Deliberately the same five minutes as the entry above: the two
        // differ in how quietly they run and in nothing else.
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "winding-down",
        name: "Winding down",
        summary: "Long, slow out-breaths for the last part of the evening.",
        technique_slug: "extended-exhale",
        goal: TechniqueGoal::Sleep,
        surface: DeliverySurface::FullScreen,
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "a-moment-to-reset",
        name: "A moment to reset",
        summary: "A minute to come down from a spike, wherever you are.",
        technique_slug: "physiological-sigh",
        goal: TechniqueGoal::Reset,
        surface: DeliverySurface::FullScreen,
        // The technique works in seconds rather than minutes, and the offer
        // should say so — a five-minute reset is a different promise.
        duration_ms: 60_000,
    },
];

/// The Start here progression: a curated order over four of the nine
/// techniques, for somebody who has not picked a goal at all (TIM-60, D2).
///
/// **Provisional copy, awaiting Tim's pass**, on the same terms as
/// [`OCCASIONS`] — TIM-28 owns every `note` below.
///
/// Array order is the ordering: the index is the `ordinal`, so the first step
/// is the first entry and the next step is whichever one the person has not
/// reached yet. Suggestive and never gating — the other five techniques are
/// listed, described and playable whether or not they appear here, and nothing
/// reads this list to decide what somebody may breathe.
///
/// Four rather than nine on purpose. A progression that names everything is the
/// catalogue in a different order; what a beginner wants is the first one, and
/// then one more.
pub(super) const PROGRESSION: &[ProgressionStepSeed] = &[
    ProgressionStepSeed {
        technique_slug: "box-breathing",
        note: "Start here. Four equal counts, nothing to remember, and it works the first time \
               you try it.",
    },
    ProgressionStepSeed {
        technique_slug: "physiological-sigh",
        note: "Next, the one that takes seconds — so there is something for the moments you \
               cannot give five minutes to.",
    },
    ProgressionStepSeed {
        technique_slug: "extended-exhale",
        note: "Then the lever underneath most of this: an out-breath longer than the in-breath, \
               with nothing to hold.",
    },
    ProgressionStepSeed {
        technique_slug: "coherent-breathing",
        note: "By now the pace is the only thing left to learn — five and a half breaths a \
               minute, no counting and no holds.",
    },
];
