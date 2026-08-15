//! The curated catalogue itself — the techniques, the foundation topics, and
//! the routes into them, as data.
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
    CopyRegister, DeliverySurface, FoundationSeed, OccasionSeed, Passage, ProgressionStepSeed,
    TechniqueGoal, TechniqueSeed, exhale, hold_in, hold_out, inhale, open_ended_stage, stage,
};

/// Array order is presentation order — `sort_order` is the index, so reordering
/// this list is the only edit needed to reorder the catalogue. Techniques are
/// grouped by goal in the order a newcomer meets them: calm first, the fast and
/// contraindicated ones well down the list.
///
/// **A sitting defaults to five minutes.** Not a house style — it is the dose
/// the trials that found anything actually ran, and it is close to the floor:
/// under five minutes a day, the studies stop moving the trait measures they
/// were built to move, and past ten to twenty the curve flattens rather than
/// climbing. So a technique somebody sits down inside opens on roughly five
/// minutes' worth of cycles, whatever its rhythm, and the cycle dial takes it
/// anywhere from one to ninety-nine after that.
///
/// The exceptions are the ones that are not sittings, and each says so where
/// its cycle count is set — a reset that works in a breath or two, a fast bout
/// that gets only dizzier with length, a child's first exercise that has to end
/// while they are still enjoying it. Reaching for one of those instead of a
/// sitting is not a smaller dose of the same thing; it is a different job, and
/// the copy on both sides is written to keep them apart.
pub(super) const TECHNIQUES: &[TechniqueSeed] = &[
    TechniqueSeed {
        slug: "box-breathing",
        name: "Box Breathing",
        summary: "Four equal counts — in, hold, out, hold. The most forgiving place to start, \
                  and the one to reach for before something stressful rather than during it.",
        // Says what the counting is *for* — the part people get wrong about box
        // breathing, treating four seconds as the target rather than the
        // scaffolding. The shape they all share is documented on
        // `TechniqueSeed::mechanism`.
        mechanism: "The holds are what make this one work. Four counts in, four held, four out, \
                    four held keeps the breath slow and even, and the two pauses let carbon \
                    dioxide rise just enough to tip you towards the recovering side of your \
                    nervous system rather than the alert one.\n\nThe counting does the rest. Four \
                    equal sides are enough to occupy the part of your mind that would otherwise \
                    be rehearsing whatever is coming, which is why military and emergency crews \
                    drill this one for composure under pressure — preparation rather than \
                    rescue, at its best in the minutes before, not in the middle.",
        evidence: "Long under-trialled for how widely it is taught, and only now catching up. In \
                   the 2023 Stanford study a month of five daily minutes did lift mood, just less \
                   than the sighing pattern it was measured against. Three 2026 studies add to \
                   that: forty-seven people tracked through hundreds of real anxiety moments \
                   found a single minute of this as calming as that sigh and easier to keep up; a \
                   sixty-six-person trial saw it blunt the rise in heart rate, anxiety and a \
                   salivary stress marker before a speech task; ninety-six police recruits handled \
                   critical-incident drills better for it while reporting no less stress. What is \
                   still missing is any sign the square itself is the reason — a 2020 trial found \
                   simply lengthening the exhale did at least as well.",
        safety_note: "",
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 8000)),
                hold_in(4000, (2000, 8000)),
                exhale(Passage::Nose, 4000, (3000, 8000)),
                hold_out(4000, (2000, 8000)),
            ],
            // Five minutes at sixteen seconds a cycle. Four of these is still
            // four of these; the cycle dial is right there for the version
            // that fits in a gap between meetings.
            19,
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
        evidence: "The best-studied pattern here, and the one with the most awkward footnote. \
                   Meta-analyses of slow paced breathing find real reductions in stress and \
                   anxiety, small to medium in size, and this pace is where most of that work was \
                   done. But a blinded trial of around four hundred people set it against a \
                   deliberately unremarkable twelve breaths a minute and found no advantage, and \
                   a 2026 trial found no gain from hunting for your own resonant rate rather than \
                   using a fixed six a minute. Some of what you feel is the pace; some of it is \
                   simply sitting down and breathing on purpose, and the trials cannot yet tell \
                   you the split.",
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
        summary: "Inhale for four, hold for seven, exhale for eight. The slow pace is doing the \
                  work — a nineteen-second round is about three breaths a minute; if the hold \
                  feels strained, shorten all three and keep the ratio.",
        mechanism: "A round takes nineteen seconds, which is about three breaths a minute — far \
                    slower than you would drift into on your own, and the slowness is the part \
                    that settles you. The long exhale is the shape that makes that pace bearable \
                    rather than the lever underneath it: your heart does ease off while you are \
                    breathing out, so the longer half is the comfortable place to spend most of \
                    the round. The hold is not there to be endured either — it lets the air \
                    settle so the long exhale has something to empty slowly, and together with \
                    the counting it gives a racing mind three small jobs and no room for a \
                    fourth.\n\nThe numbers are Andrew Weil's, put on a much older pranayama \
                    ratio, and he points it where it belongs: the end of the day. He also caps \
                    it — four rounds starting out, eight at the most in a first month — which is \
                    why this is the one exercise here that does not open on five minutes. Eight \
                    is where it starts and the dial goes down; four is plenty on a night when \
                    the hold feels like work. It is not a sedative, and no number of rounds will \
                    switch you off, but it reliably trades rehearsing tomorrow for something \
                    slower, which is the state sleep starts from.",
        evidence: "More trials than it used to have, and none of them hard to please. A 2025 \
                   review gathered fifteen studies, consistently positive on stress and anxiety, \
                   and the years since have added clinical ones: forty-eight people with tinnitus \
                   whose insomnia scores improved, a chronic lung disease group whose sleep \
                   quality did. All unblinded, all measured against simply being handed \
                   information, and none of them run in people who only want to sleep better. \
                   What the wider research supports is the pace: three breaths a minute is well \
                   inside the slow range the meta-analyses cover, if slower than the five or six \
                   they cluster at. The famous counts are tradition rather than a finding — \
                   nothing has shown four, seven and eight to beat any other way of arriving at \
                   the same unhurried breathing.",
        safety_note: "",
        goal: TechniqueGoal::Sleep,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 6000)),
                hold_in(7000, (4000, 10000)),
                exhale(Passage::Mouth, 8000, (6000, 12000)),
            ],
            // Weil's own ceiling for a first month, and the one place the
            // five-minute convention gives way: five minutes of this would be
            // sixteen rounds, twice what the person who wrote it allows, and
            // over half of those minutes are breath-hold rather than moving
            // air. Not a number to arrive at by arithmetic.
            8,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "extended-exhale",
        name: "Extended Exhale",
        summary: "In for four, out for six. A slow breath in the shape that is easiest to hold \
                  onto — nothing to count and no hold to strain against. Stretch the exhale \
                  towards eight when six stops feeling like enough.",
        mechanism: "Ten seconds a round is six breaths a minute, and it is that pace that does \
                    the settling — the trials that varied the ratio directly found the longer \
                    exhale adds little on top of it. What the long out-breath buys you is a shape \
                    you can keep: your heart eases off while you are breathing out, so the longer \
                    half is the comfortable one to stretch, and there is nothing to concentrate \
                    on. And because it is a ratio rather than a fixed pace, it meets your \
                    breathing wherever it happens to be, wound up or already half asleep.\n\n\
                    Reach for it when a hold would be work and a fixed count would be a fight: \
                    last thing at night, already lying down, or still catching your breath after \
                    effort. If you can sigh, you can do this.",
        evidence: "The pace is evidenced; the ratio is not. Two studies that varied the two \
                   independently — one of over eight hundred people in 2024, and a twelve-week \
                   trial the year before — found that how slowly you breathe predicts how calm \
                   you feel, while making the exhale longer than the inhale adds nothing \
                   measurable on top. That is not a reason to drop the long exhale: it is the \
                   easiest way to arrive at a slow breath without counting. It is a reason not to \
                   believe anyone who tells you the ratio is the active ingredient.",
        safety_note: "",
        goal: TechniqueGoal::Sleep,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 5000)),
                // Six to eight is the range the evidence is gathered at, and the
                // one the summary invites people to walk up.
                exhale(Passage::Nose, 6000, (6000, 8000)),
            ],
            // Five minutes at ten seconds a cycle. Nothing about lying in bed
            // argues for less: this is the one people fall asleep partway
            // through, and a session that ends early because they did is not a
            // session that went wrong.
            30,
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
                    purpose is recent science rather than old practice. A slow mouth exhale can \
                    make the release feel more like a sigh, but the route is a comfort choice \
                    rather than the mechanism.\n\nIt is a spike tool, not a sitting: use it at the moment \
                    something lands — the email, the near miss, the door about to open. A round \
                    or two is the full effect; after that it is just breathing.",
        evidence: "Strong on the physiology, and no longer untested at the dose you would \
                   actually use. That a second inhale reopens collapsed air sacs, and that the \
                   exhale after it unloads more carbon dioxide, is not in dispute. What the 2023 \
                   Stanford trial tested, though, was something else: five minutes of this \
                   pattern a day for a month — the cyclic sighing dose, not a round or two \
                   mid-spike — on about thirty people an arm. Using it in the moment has its own \
                   study now. Forty-seven people carried it into nearly eight hundred real \
                   anxiety moments in 2026, took roughly a minute of it against a control, and \
                   came down. It is a pilot, for all that its plan was filed before it ran, and \
                   box breathing did exactly as well in the same study — so what it supports is \
                   reaching for something, not reaching for this.",
        safety_note: "",
        goal: TechniqueGoal::Reset,
        stages: &[stage(
            // Two consecutive INHALE phases, deliberately. The second sip
            // re-inflates collapsed alveoli, and it is a distinct beat the
            // client must cue separately — merging them into one long inhale
            // loses the technique.
            //
            // The sip runs a second rather than the 0.7s it was authored at.
            // Sharpness is the point and a long second inhale is not a sip,
            // but 0.7s is barely longer than the cue announcing it: the word
            // lands, and the phase is over about as soon as somebody has
            // understood it. A second is still two-thirds of the first inhale
            // and unmistakably the smaller of the pair, and the dial still
            // reaches down to 0.5s for anybody who wants it sharper.
            &[
                inhale(Passage::Nose, 1500, (1000, 2500)),
                inhale(Passage::Nose, 1000, (500, 1200)),
                exhale(Passage::Nose, 5000, (4000, 8000)),
            ],
            // The summary promises "one or two rounds"; three is the generous
            // end of that, and the technique loses its point when stretched
            // into a session.
            3,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
    // A technique rather than a long-dose occasion pointing at
    // `physiological-sigh`, which is where dose normally lives (see
    // `OCCASIONS`). An occasion can set how many minutes a session runs and
    // nothing else, and what the trial dosed was not five minutes of the sigh:
    // it was a slower cycle — ten seconds against seven and a half — with a
    // longer first breath, because a pattern built for one sharp reset is not
    // one you can sit inside for five minutes. Different phase durations mean a
    // different technique, and this catalogue has no other way to say so.
    TechniqueSeed {
        slug: "cyclic-sighing",
        name: "Cyclic Sighing",
        summary: "The sigh again — a full breath in, a short sip on top, a long breath out — but \
                  five unhurried minutes of it rather than a round or two. This is the daily \
                  version, and the one with a month-long trial behind it.",
        mechanism: "Each sigh does the same small job the single one does: the second sip \
                    re-inflates air sacs that have started to fall shut, and the long exhale \
                    after it carries an unusual amount of carbon dioxide out. Strung together for \
                    five minutes it stops being a reset and becomes a pace — thirty rounds of ten \
                    seconds is six breaths a minute, squarely in the range slow breathing is \
                    studied at, with an exhale long enough that you never have to work at keeping \
                    it slow. A slow mouth exhale can make each release feel more natural, but it \
                    is optional; the trial asked people to use the nose when comfortable.\n\nThis \
                    is the physiological sigh's daily sibling, and the dose is \
                    the whole difference between them: that one is for the moment something \
                    lands, this one is for the month. Five minutes is the length the trial it \
                    comes from used, rather than a number somebody liked, which is why the \
                    session runs thirty rounds and stops. Treat it as a habit rather than an \
                    intervention — a short sitting most days, at whatever time you will actually \
                    keep.",
        evidence: "The best-evidenced protocol in the catalogue, and still the least replicated. A \
                   2023 Stanford trial had people do five minutes of it a day for a month: daily \
                   mood improved more than with mindfulness meditation or two other breathing \
                   patterns, resting breathing rate came down, and the people who practised on \
                   more days got more from it — which is the shape you want to see if the \
                   breathing is what is doing the work. But it was about thirty people an arm in \
                   one laboratory, nobody has run that month again since, and there is no way to \
                   tell whether the sighs matter or five quiet minutes a day would have done it \
                   anyway. What has arrived instead is two outside looks at shorter doses, and \
                   they split: eighty-one people waiting for orthopaedic appointments in 2025 did \
                   four minutes and reported less pain but no less anxiety, and a 2026 field \
                   study of a single minute at real anxiety moments found box breathing every bit \
                   as good.",
        safety_note: "",
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            // Two consecutive inhales for the same reason as the physiological
            // sigh's, and at different lengths from it deliberately: the two
            // techniques must not draw or speak as the same figure, and the
            // longer first breath is what makes five minutes of this sustainable
            // where the sigh's sharper one is built for a single reset.
            //
            // The sip's 0.5s floor is the watch haptic floor, matching the sigh.
            &[
                inhale(Passage::Nose, 2000, (1500, 3000)),
                inhale(Passage::Nose, 1000, (500, 1500)),
                exhale(Passage::Nose, 7000, (5000, 10000)),
            ],
            // Thirty ten-second cycles is the trial's five minutes a day, which
            // is the entire claim this technique makes. Shortening it would
            // leave the copy citing a dose the session does not run.
            30,
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
        evidence: "Traditional practice with small studies under it. Short bouts of fast yogic \
                   breathing have been shown to raise heart rate and shift measures of alertness \
                   and reaction time, in trials of a few dozen people at a time and none of them \
                   blinded. The direction is not really in doubt — over-breathing is stimulating, \
                   which you can feel — but the size of the effect, and whether it beats standing \
                   up and walking about, is unstudied.",
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
        evidence: "The most honest entry here, because the best trial of it is a null. A blinded \
                   study of about two hundred people set this style of fast breathing and \
                   breath-holding against a gentle sham and found no benefit on stress, mood or \
                   inflammation — and more side effects in the group doing the real thing. \
                   Another, in eighty-four women, matched the method plus cold exposure against \
                   eight breaths a minute plus warm showers, and the two came out level. People \
                   who practise it are describing something real; what has not been shown is that \
                   the hyperventilating and the holding are what produce it.",
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
            // ending it early is an ordinary way to breathe this. The range is
            // the band a practised hold typically runs — the figure and steps
            // print it as an example (`hold · 30s–2m`), and its dial moves the
            // first round's aim within it.
            open_ended_stage(&[hold_out(30000, (30000, 120_000))]),
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
        evidence: "No trials of its own, and few of the box it lengthens. The long sides are a \
                   craft judgement — more to keep track of, so more of your attention is spoken \
                   for — and the evidence underneath is the same slow-breathing literature that \
                   carries every calm pattern here, which has nothing to say about counting to \
                   six rather than four. Read the focus framing as a description of how it feels \
                   to do, not as a finding about attention.",
        safety_note: "",
        goal: TechniqueGoal::Focus,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 6000, (4000, 10000)),
                hold_in(6000, (4000, 10000)),
                exhale(Passage::Nose, 6000, (4000, 10000)),
                hold_out(6000, (4000, 10000)),
            ],
            // Five minutes at twenty-four seconds a cycle — the same dose as
            // box breathing at a pace that asks more of you.
            13,
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
        evidence: "Better studied than it sounds, and shakier than the totals suggest. A 2024 \
                   meta-analysis pooled the blood-pressure trials and found meaningful \
                   reductions, but the studies disagreed with one another enormously — over \
                   three-quarters of the variation was between trials rather than within them, \
                   which is the statistical way of saying the pooled number is not describing one \
                   effect. The anxiety work is still pilot-sized, and what there is of it argues \
                   against grabbing this in a bad moment: a 2024 review of brief interventions \
                   for anxiety in the moment found this one came out behind its control, and the \
                   single trial that put thirty people in front of a simulated audience found \
                   nothing either way. As the unhurried sitting it is written to be, fine; as a \
                   rescue, no. And nothing has separated the nostrils from what they are wrapped \
                   around, which is slow nasal breathing with something to concentrate on.",
        safety_note: "",
        goal: TechniqueGoal::Focus,
        stages: &[stage(
            &[
                inhale(Passage::LeftNostril, 4000, (3000, 6000)),
                exhale(Passage::RightNostril, 6000, (4000, 8000)),
                inhale(Passage::RightNostril, 4000, (3000, 6000)),
                exhale(Passage::LeftNostril, 6000, (4000, 8000)),
            ],
            // Five minutes at twenty seconds a cycle. The switching stops
            // needing thought around three minutes in, which the mechanism
            // promises and a three-minute session used to end on.
            15,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
];

/// Array order is reading order, same as the catalogue. Practice leads because
/// it is the useful decision: choose a comfortable, studied exercise and come
/// back to it. The refinements follow, then the higher-care practices, the
/// uncertain dose, and the boundary of what the evidence and the app can claim.
pub(super) const FOUNDATIONS: &[FoundationSeed] = &[
    FoundationSeed {
        slug: "what-matters-most",
        question: "Practice matters more than perfect",
        answer: "Research does not point to one ideal pattern; it supports modest benefits from \
                 deliberate breathing, especially comfortable slow practices repeated over time. \
                 Choose a well-studied exercise you will return to. Nose breathing, belly movement \
                 and exact counts are refinements, not pass/fail rules. Fast breathing and long \
                 holds need extra care.",
    },
    FoundationSeed {
        slug: "what-a-good-breath-feels-like",
        question: "What should a good breath feel like?",
        answer: "Quiet and comfortable, not the biggest breath you can take. Let your ribs and belly \
                 move without forcing them. If you feel air hunger, tingling or dizziness, make the \
                 breath smaller or return to normal breathing. Stop if the feeling does not settle.",
    },
    FoundationSeed {
        slug: "why-it-works",
        question: "Why can slow breathing help?",
        answer: "Your heart naturally speeds a little as you breathe in and slows as you breathe \
                 out. Slowing the cycle makes those swings larger and can increase heart-rate \
                 variability while you practise. That change is reliable; feeling calmer is common \
                 but less consistent, so treat it as a useful nudge rather than a switch.",
    },
    FoundationSeed {
        slug: "belly-or-chest",
        question: "Belly or chest?",
        answer: "Let the breath move low if that feels easy. The diaphragm does most of the work, \
                 and a hand below your ribs can help you notice it. Your chest will still move, and \
                 that is not a mistake. Do not force the belly outward or turn the breath into an \
                 effort.",
    },
    FoundationSeed {
        slug: "nose-or-mouth",
        question: "Nose or mouth?",
        answer: "Use your nose when it is comfortable: it filters, warms and humidifies incoming \
                 air, and the narrower route can make a slow pace easier. Breathe out through your \
                 nose or softly pursed lips. If you are congested or uncomfortable, use your mouth; \
                 the practice still counts.",
    },
    FoundationSeed {
        slug: "how-slow",
        question: "How slow?",
        answer: "Aim for slower than usual without straining. Five or six breaths a minute is \
                 common in research, not a test you have to pass. If the guide leaves you short of \
                 air, shorten the count or breathe normally. Comfort matters more than reaching the \
                 displayed number.",
    },
    FoundationSeed {
        slug: "fast-breathing-and-holds",
        question: "What about fast breathing and holds?",
        answer: "Treat both as optional techniques, not upgrades. Fast breathing can lower carbon \
                 dioxide and cause tingling, dizziness or fainting; practise it seated or lying \
                 down, never driving or near water. Keep holds comfortable and skip them if you \
                 finish gasping. The slower exercises work without either.",
    },
    FoundationSeed {
        slug: "getting-comfortable",
        question: "How should I get comfortable?",
        answer: "Sit when you want to stay alert; lie down when you are settling for sleep. Keep \
                 your posture easy rather than rigid. Close your eyes, soften your gaze or watch \
                 the guide—choose whichever feels safest and requires the least effort.",
    },
    FoundationSeed {
        slug: "how-long",
        question: "How long and how often?",
        answer: "One comfortable minute may help in the moment. Studies looking for changes over \
                 weeks often use five-to-ten-minute sessions repeated on most days, but the best \
                 dose is not settled. Start with a length you will repeat; more time is not \
                 automatically better.",
    },
    FoundationSeed {
        slug: "how-good-is-the-evidence",
        question: "How good is the evidence?",
        answer: "Promising, modest and uneven. Randomised trials find small-to-medium improvements \
                 in stress and anxiety overall, but many are small or at risk of bias. Slow \
                 breathing reliably changes heart-rate variability while you practise; lasting \
                 emotional or blood-pressure benefits are less certain. No single pattern has \
                 proved best, so prefer well-studied, comfortable exercises and keep medical \
                 treatment unchanged.",
    },
    FoundationSeed {
        slug: "why-no-scores",
        question: "Why doesn't önd score you?",
        answer: "Because a breathing number is not a health verdict. Carbon-dioxide tolerance \
                 targets, coherence scores and breathing ages are not established measures of \
                 whether your life or health is improving. önd keeps what it can support—what you \
                 practised, for how long and how it felt—and compares your resting rate only with \
                 your own.",
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
        slug: "five-minutes-today",
        name: "Five minutes today",
        summary: "No particular reason — just the daily one, done most days. This is the one the \
                  evidence is about.",
        // The only entry that is not a situation, and first because of it: the
        // evidence for breathing at all is evidence for regularity, so the
        // reason somebody opens the app on an ordinary day deserves a door of
        // its own rather than being reached through a moment they are not
        // having.
        technique_slug: "cyclic-sighing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        // Five minutes exactly, which is the technique's own thirty cycles and
        // the dose the trial ran. The one duration here that is a finding
        // rather than a judgement about somebody's afternoon.
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "before-a-presentation",
        name: "Before a presentation",
        summary: "Steady the nerves in the few minutes before you walk in.",
        technique_slug: "box-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
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
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
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
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
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
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
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
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "with-your-child",
        name: "With your child",
        summary: "A first breathing exercise to do together, in words a small child can follow.",
        technique_slug: "extended-exhale",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Playful,
        // This rhythm belongs to doing the exercise with a child, not to
        // Extended Exhale as a standalone exercise.
        phase_durations_ms: &[3000, 5000],
        safety_note: "This is for breathing alongside a child, not for teaching one to hold \
                      their breath. There are no holds here and none should be added — \
                      breath-holding and fast breathing are not for children. Stop if they feel \
                      dizzy, or if they have stopped enjoying it.",
        // Ninety seconds — eleven cycles of the eight-second rhythm. Long enough
        // to settle, short enough to finish before a child is finished with it.
        duration_ms: 90_000,
    },
    OccasionSeed {
        slug: "a-moment-to-reset",
        name: "A moment to reset",
        summary: "A minute to come down from a spike, wherever you are. This one is for the \
                  moment, not for the month.",
        technique_slug: "physiological-sigh",
        goal: TechniqueGoal::Reset,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        // The technique works in seconds rather than minutes, and the offer
        // should say so — a five-minute reset is a different promise.
        duration_ms: 60_000,
    },
];

/// The Start here progression: a curated order over part of the catalogue, for
/// somebody who has not picked a goal at all (TIM-60, D2).
///
/// **Provisional copy, awaiting Tim's pass**, on the same terms as
/// [`OCCASIONS`] — TIM-28 owns every `note` below.
///
/// Array order is the ordering: the index is the `ordinal`, so the first step
/// is the first entry and the next step is whichever one the person has not
/// reached yet. Suggestive and never gating — the techniques it leaves out are
/// listed, described and playable whether or not they appear here, and nothing
/// reads this list to decide what somebody may breathe.
///
/// A few rather than all of them on purpose. A progression that names everything
/// is the catalogue in a different order; what a beginner wants is the first
/// one, and then one more.
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
        technique_slug: "cyclic-sighing",
        note: "Then the same breath as a sitting rather than a rescue — five minutes of it, which \
               is the one dose here a month-long trial actually measured.",
    },
    ProgressionStepSeed {
        technique_slug: "extended-exhale",
        note: "Then the slow one you can do lying down: an out-breath longer than the in-breath, \
               with nothing to count and nothing to hold.",
    },
    ProgressionStepSeed {
        technique_slug: "coherent-breathing",
        note: "By now the pace is the only thing left to learn — five and a half breaths a \
               minute, no counting and no holds.",
    },
];
