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
        // Says what the counting is *for* — the part people get wrong about box
        // breathing, treating four seconds as the target rather than the
        // scaffolding. The shape all nine share is documented on
        // `TechniqueSeed::mechanism`.
        mechanism: "The holds are what make this one work. Four counts in, four held, four out, \
                    four held keeps the breath slow and even, and the two pauses let carbon \
                    dioxide rise just enough to tip you towards the recovering side of your \
                    nervous system rather than the alert one.\n\nThe counting does the rest. Four \
                    equal sides are enough to occupy the part of your mind that would otherwise \
                    be rehearsing whatever is coming, which is why military and emergency crews \
                    drill this one for composure under pressure — preparation rather than \
                    rescue, at its best in the minutes before, not in the middle.",
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
        mechanism: "Your heart speeds up a little on every breath in and slows on every breath \
                    out, and at about five and a half breaths a minute those swings line up with \
                    the slower rhythm your blood pressure runs on. Every breath then presses the \
                    calming side of your nervous system at exactly the moment it is listening. \
                    This one came from the lab rather than the tradition — worked out by \
                    researchers training heart-rate variability — and it carries the strongest \
                    trial support in the catalogue.\n\nThe settling is cumulative rather than \
                    instant: it arrives over minutes, not breaths, and deepens the longer you \
                    stay. That makes this the one to sit with when you have the time — after \
                    something hard, through something long — rather than the one to grab in the \
                    thirty seconds before it.",
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
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "four-seven-eight",
        name: "4-7-8 Breathing",
        summary: "Inhale for four, hold for seven, exhale for eight. The long exhale is doing the \
                  work; if the hold feels strained, shorten all three and keep the ratio.",
        mechanism: "The exhale is twice the length of the inhale, and the out-breath is the half \
                    of the cycle where your heart slows — so nearly all of each round is spent \
                    leaning on the brake. The hold is not there to be endured: it lets the air \
                    settle so the long exhale has something to empty slowly, and together with \
                    the counting it gives a racing mind three small jobs and no room for a \
                    fourth.\n\nThe numbers are Andrew Weil's, put on a much older pranayama \
                    ratio, and he points it where it belongs: the end of the day. It is not a \
                    sedative — four cycles will not switch you off — but it reliably trades \
                    rehearsing tomorrow for something slower, which is the state sleep starts \
                    from.",
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
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "extended-exhale",
        name: "Extended Exhale",
        summary: "In for four, out for six. The same lever 4-7-8 pulls — an out-breath longer \
                  than the in-breath — with no hold to strain against. Stretch the exhale towards \
                  eight when six stops feeling like enough.",
        mechanism: "Your heart quickens slightly on every breath in and slows on every breath \
                    out, so a cycle that spends longer breathing out than in comes out ahead on \
                    slowing — every round, automatically, with nothing to concentrate on. And \
                    because it is a ratio rather than a fixed pace, it meets your breathing \
                    wherever it happens to be, wound up or already half asleep.\n\nReach for it \
                    when a hold would be work and a fixed count would be a fight: last thing at \
                    night, already lying down, or still catching your breath after effort. If \
                    you can sigh, you can do this.",
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
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "physiological-sigh",
        name: "Physiological Sigh",
        summary: "A full inhale, a second short sip of air on top, then a long slow exhale. \
                  One or two rounds is the whole exercise — it works in seconds, not minutes.",
        mechanism: "The second sip of air is the trick. Under stress the small air sacs of the \
                    lungs start to fall shut, and one inhale stacked on another pops them open \
                    again, so the long exhale that follows carries far more carbon dioxide out \
                    in a single breath. That one big unloading takes the edge off arousal within \
                    a breath or two — the same reflex a sob runs on its way out, and one your \
                    body already fires every few minutes without telling you. Doing it on \
                    purpose is recent science: in a 2023 Stanford trial it beat meditation and \
                    two other breathing patterns at lifting mood.\n\nIt is a spike tool, not a \
                    sitting: use it at the moment \
                    something lands — the email, the near miss, the door about to open. A round \
                    or two is the full effect; after that it is just breathing.",
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
        mechanism: "Quick, forceful breathing is the breathing of exertion, and running it on \
                    purpose persuades the body the exertion has started: heart rate climbs, \
                    adrenaline rises, and the fog lifts. The same speed blows off carbon \
                    dioxide faster than the body makes it, which is where the light head comes \
                    from — and why the bout is short and the chair is not optional.\n\nThis is \
                    bhastrika, the yoga tradition's bellows breath, and the tradition's rules \
                    for it — seated, brief — are the same ones the safety note repeats. Use it \
                    where you might otherwise use caffeine: a slow morning, the mid-afternoon \
                    dip, the minutes before a workout. Forty seconds is plenty — past that you \
                    are not getting more alert, only dizzier.",
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
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "wim-hof-rounds",
        name: "Wim Hof-style Rounds",
        summary: "Thirty full, unforced breaths and one last deep one, then let the air go and \
                  wait — the hold after them is the point, and it lasts as long as it lasts. One \
                  deep breath in, held for fifteen seconds, closes each round. Popular, well \
                  described by people who practise it, and thinner on trial evidence than its \
                  reputation suggests.",
        mechanism: "Thirty deep, quick breaths clear far more carbon dioxide than usual, and \
                    carbon dioxide — not lack of oxygen — is what drives the urge to breathe: \
                    with that trigger pushed back, an empty-lung hold that should feel desperate \
                    is suddenly roomy. The same over-breathing spikes adrenaline, which is the \
                    bright, slightly electric feel of a round, and the tingling that can come \
                    with it is chemistry, not achievement or alarm.\n\nThe method is one man's \
                    packaging of much older practice — Hof adapted it from Tibetan tummo \
                    breathing — and it works best treated the same way: a practice you set \
                    aside time for rather than a fix grabbed in passing, three rounds in ten \
                    unhurried minutes. The hold ends whenever you decide it does: comfort is \
                    the protocol, and pushing past it is the one way to breathe this wrong.",
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
            // Its duration is what the first round suggests aiming for, and the
            // session grows it by that much again each round — thirty seconds,
            // then a minute, then ninety — because a hold taken after more of
            // the protocol is one somebody can settle into for longer. A
            // suggestion, never a requirement: the person ends the hold, and
            // ending it early is an ordinary way to breathe this. The range is a
            // single point because there is no dial here at all.
            open_ended_stage(&[hold_out(30000, (30000, 30000))]),
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
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "long-box-breathing",
        name: "Long Box Breathing",
        summary: "Box breathing with longer sides — six counts each, or eight once six feels \
                  easy. The hold is what makes it a focus exercise rather than a calming one: \
                  there is enough to keep track of that there is no room left to drift.",
        mechanism: "The concentration is not a side effect — it is the exercise. At six counts \
                    a side each phase is long enough that it has to be steered rather than left \
                    to habit, and the holds are where a wandering mind gets caught: nothing is \
                    moving, so the count is all there is to hold on to. Underneath the effort it \
                    is still slow, even breathing, which is why the alertness it builds is a \
                    calm one.\n\nUse it at the threshold of work that needs sustained attention, \
                    not in a break from it: a few minutes before the deep block, warming up the \
                    same faculty the work is about to spend.",
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
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "alternate-nostril",
        name: "Alternate-Nostril Breathing",
        summary: "Thumb closes the right nostril, ring finger the left. In through the left, out \
                  through the right, in through the right, out through the left — that sequence \
                  is one cycle, and the four beats on screen are its four breaths in order. A \
                  traditional practice with modest trial support and an unmistakable knack for \
                  holding attention.",
        mechanism: "The hand is the mechanism. Which finger, which side, which direction — the \
                    switching is choreography that cannot run on autopilot, so attention has \
                    nowhere to spare and settles, for once, entirely on the breath. The yoga \
                    tradition has run it this way for centuries as nadi shodhana, and \
                    underneath the choreography it is still slow breathing through the nose — \
                    which is why a practice that reads like a puzzle leaves you calm as well \
                    as collected.\n\nIt suits the \
                    seam between doing one thing and starting another — the desk just sat down \
                    at, the minutes after arriving. Three minutes in, the switching stops \
                    needing thought, and what is left is a quiet, occupied steadiness that \
                    follows you into whatever comes next.",
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
        requires_subscription: false,
    },
];

/// Array order is reading order, same as the catalogue. These are ordered the
/// way the questions occur to someone learning: why bother at all, what moves,
/// what it goes through, how slow to go — then the two questions that only
/// arrive once the slow pattern is familiar, what fast does and what a hold
/// does — then where to sit, what to do with your eyes, and finally the two
/// about the practice rather than the breath: how long a sitting is worth, and
/// whether any of it lasts.
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
        slug: "breathing-fast",
        question: "What if I breathe quickly?",
        answer: "Then you get the opposite of settling, which is occasionally the point. Breathing \
                 fast lifts your heart rate and clears carbon dioxide quicker than your body makes \
                 it, and it is that shortage — not any lack of oxygen — behind the tingling lips \
                 and light head people meet in their first fast round. The two halves are not \
                 symmetrical either: a quick breath in is a small jolt of alertness, which is why \
                 a sigh takes its sip sharply and lets the long part happen on the way out. So if \
                 you are trying to calm down, take the in-breath at whatever speed suits you, as \
                 long as the out-breath is the longer one — and leave the deliberately fast \
                 patterns to the exercises built around them, sitting down.",
    },
    FoundationSeed {
        slug: "holding-the-breath",
        question: "What about holding it?",
        answer: "A pause, not a test — and the two pauses do different things. Holding after the \
                 out-breath, with your lungs empty, is the settling one: nothing is stretched, and \
                 the slow rise in carbon dioxide is what teaches your body to stop treating that \
                 feeling as an emergency. Holding after the in-breath is more work — a full chest \
                 kept under pressure — which is why box breathing keeps both its holds short and \
                 equal rather than long. Comfortable is the whole measure: come out of one gasping \
                 and it was too long, and the breath after a hold should be an ordinary one rather \
                 than a bigger one. Every pattern here still works with the holds left out.",
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
    FoundationSeed {
        slug: "how-long",
        question: "How long is helpful?",
        answer: "Less than you would think, and more often than you would think. One slow minute \
                 changes how you feel now; five to ten is where most of the research sits, and it \
                 is what the sessions here are built around. Past twenty the returns flatten, and \
                 a long sitting has the added disadvantage of being the easy one to skip. Little \
                 and often wins: the same half hour spread across a week does more than the same \
                 half hour in one go, because what you are after is a body that reaches for the \
                 longer exhale on its own.",
    },
    FoundationSeed {
        slug: "long-term-benefits",
        question: "Does it do anything long term?",
        answer: "Yes, modestly, and on better evidence than most breathing claims. Trials that run \
                 slow breathing over weeks find lower blood pressure, higher heart-rate \
                 variability and lower anxiety and stress scores, and a month of five minutes a \
                 day has been enough to move mood measures in more than one of them. The effects \
                 are real but sized like a good habit rather than a medicine — worth having, not \
                 worth stopping anything you are being treated for. What those studies share is \
                 regularity: most days for a month or two, rather than an hour once a fortnight.",
    },
];

/// The occasion entries: why somebody opened the app, and where that routes.
///
/// **Provisional copy, awaiting Tim's pass.** TIM-28 owns the final words for
/// every `name` and `summary` here, and the working set itself is a draft — the
/// moments below exist so TIM-19 and TIM-128 have something real to build
/// against. What is *not* provisional is the shape: an occasion resolves to a
/// technique that already exists, a goal it borrows, a surface, and a duration
/// (TIM-60, D1).
///
/// Array order is presentation order — `sort_order` is the index, as in
/// [`TECHNIQUES`].
///
/// Every entry routes to something the person can breathe, which is now true by
/// construction rather than by curation — the catalogue is free throughout. If a
/// subscription gate comes back, this list is where it bites first: an occasion
/// is the entry point somebody meets before they have chosen anything, and one
/// that opens onto a locked technique is a worse first impression than not
/// offering the moment at all.
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
        slug: "after-a-workout",
        name: "After a workout",
        summary: "Bring your breathing down once the hard part is over.",
        // An out-breath longer than the in-breath, rather than coherent
        // breathing's fixed five and a half a minute. Straight off hard cardio
        // the drive to breathe is still elevated while CO₂ clears, and a fixed
        // rate would be asking somebody to underbreathe through it. A ratio
        // works at whatever rate they arrive at, which is the only thing here
        // that can be true of everybody.
        technique_slug: "extended-exhale",
        // Borrowed rather than inherited, and the one entry where that
        // distinction does any work: the technique is grouped under sleep, and
        // coming down from a session is not going to bed.
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        // Three minutes, on `before-a-presentation`'s reasoning in a different
        // room: the five the other recovery entries ask for is a promise nobody
        // standing in a gym still catching their breath actually keeps.
        duration_ms: 180_000,
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
