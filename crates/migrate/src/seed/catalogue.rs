//! The curated catalogue itself — the techniques, the foundation topics, and
//! the routes into them, as data. Apart from `super` because this file changes
//! when a technique's phrasing or timing does, and `seed` when the way reference
//! data reaches the database does. A child of `seed` rather than a sibling, so
//! the seed structs and their `const fn` builders stay unreachable elsewhere.

use super::{
    CopyRegister, DeliverySurface, EvidenceGrade, FoundationSeed, HapticPattern, Manner,
    OccasionSeed, Passage, ProgressionStepSeed, ReadingContentSeed, TechniqueGoal, TechniqueSeed,
    exhale, hold_in, hold_out, inhale, open_ended_stage, shaped_exhale, shaped_inhale, stage,
};

const fn prose(lead: &'static str) -> ReadingContentSeed {
    ReadingContentSeed::prose(lead)
}

const fn bullets(lead: &'static str, items: &'static [&'static str]) -> ReadingContentSeed {
    ReadingContentSeed::bullets(lead, items)
}

const fn numbered(lead: &'static str, items: &'static [&'static str]) -> ReadingContentSeed {
    ReadingContentSeed::numbered(lead, items)
}

/// Array order is presentation order — `sort_order` is the index. Techniques are
/// grouped by goal in the order a newcomer meets them: calm first, the fast and
/// contraindicated ones last. A sitting opens on five minutes, the dose the
/// trials ran (`docs/product/breathing-science.md` §2); each exception says so
/// where its cycle count is set.
pub(super) const TECHNIQUES: &[TechniqueSeed] = &[
    TechniqueSeed {
        slug: "box-breathing",
        name: "Box Breathing",
        summary: "Four even counts give you a steady rhythm and a simple focus before a stressful moment.",
        // Says what the counting is *for* — the part people get wrong about box
        // breathing, treating four seconds as the target rather than the
        // scaffolding. The shape they all share is documented on
        // `TechniqueSeed::mechanism`.
        mechanism: bullets(
            "Box breathing can help you feel composed by slowing the breath and giving your attention one clear task.",
            &[
                "Equal counts keep the rhythm steady and easy to follow.",
                "Two comfortable pauses slow the cycle without asking for a very long breath.",
                "Counting can interrupt the mental rehearsal that often builds before pressure.",
            ],
        ),
        evidence: bullets(
            "Research is growing, though it does not show that the square pattern is uniquely effective.",
            &[
                "In a 2023 study, five daily minutes for a month improved mood, but less than cyclic sighing.",
                "Three 2026 studies found benefits during anxiety, public speaking and critical-incident training.",
                "A 2020 trial found that simply lengthening the breath out worked at least as well.",
            ],
        ),
        evidence_grade: EvidenceGrade::Moderate,
        safety_note: "",
        preparation: prose(""),
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 8000)),
                // The release out of a held chest is the one turn in a square
                // that is not square, and the empty hold is nearly as slow.
                hold_in(4000, (2000, 8000)).with_gap(150),
                exhale(Passage::Nose, 4000, (3000, 8000)),
                hold_out(4000, (2000, 8000)).with_gap(120),
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
        summary: "A smooth, even rhythm can help your body settle over a few quiet minutes.",
        mechanism: bullets(
            "Coherent breathing can help the rhythms of your breath, heart and blood pressure work together more smoothly.",
            &[
                "Your heart speeds up as you breathe in and slows as you breathe out.",
                "At this pace, those changes can line up with the slower rhythm of blood pressure.",
                "The effect builds over minutes, making this a useful exercise when you have time to settle.",
            ],
        ),
        evidence: bullets(
            "This is one of the best-studied patterns in the catalogue, with some important limits.",
            &[
                "Reviews of slow paced breathing find small to medium reductions in stress and anxiety.",
                "A blinded trial of about 400 people found no advantage over breathing at 12 breaths per minute.",
                "A 2026 trial found no added benefit from finding a personal rate instead of using six breaths per minute.",
            ],
        ),
        evidence_grade: EvidenceGrade::Moderate,
        safety_note: "",
        preparation: prose(""),
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
        summary: "A very slow 4-7-8 rhythm can give a busy mind something simple to follow as you wind down.",
        mechanism: bullets(
            "4-7-8 breathing can help you slow down at the end of the day by stretching each round to about 19 seconds.",
            &[
                "The long breath out makes the very slow pace easier to maintain.",
                "The hold and the counting keep your attention on three simple tasks.",
                "Shorten every part if the hold feels strained. A comfortable rhythm matters more than the exact count.",
            ],
        ),
        evidence: bullets(
            "The wider evidence supports slow breathing, but not the special power of the 4-7-8 counts.",
            &[
                "A 2025 review of 15 studies reported improvements in stress and anxiety.",
                "Small clinical studies have also reported better sleep, but they were unblinded and used weak comparisons.",
                "No study has shown that 4-7-8 works better than another comfortable way to breathe this slowly.",
            ],
        ),
        evidence_grade: EvidenceGrade::Moderate,
        safety_note: "",
        preparation: prose(""),
        goal: TechniqueGoal::Sleep,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 4000, (3000, 6000)),
                // 250 opens the mouth after a seven-second hold. 200 stops the
                // hurried inhale that is this exercise's classic failure.
                hold_in(7000, (4000, 10000)).with_gap(250),
                exhale(Passage::Mouth, 8000, (6000, 12000)).with_gap(200),
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
        summary: "A gentle four-in, six-out rhythm can make slow breathing easy to follow without a hold.",
        mechanism: bullets(
            "Extended Exhale can help you settle into a slow rhythm without the effort of a breath hold.",
            &[
                "A four-in, six-out cycle gives you six breaths per minute.",
                "The longer breath out is often the easiest part of the cycle to stretch comfortably.",
                "The simple ratio suits you whether you feel wound up or nearly asleep.",
            ],
        ),
        evidence: bullets(
            "Research supports the slow pace more clearly than the longer breath out.",
            &[
                "A 2024 study of more than 800 people linked slower breathing with feeling calmer.",
                "A 12-week trial also found that pace mattered more than the ratio between breathing in and out.",
                "The longer breath out may still be useful because it makes a slow rhythm easier to follow.",
            ],
        ),
        evidence_grade: EvidenceGrade::Moderate,
        safety_note: "",
        preparation: prose(""),
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
        summary: "One or two double breaths in, then a long breath out, can quickly ease a sudden spike.",
        mechanism: bullets(
            "A physiological sigh can help your body reset quickly by opening more of the lungs before a long release.",
            &[
                "The second short breath in reopens small air sacs that may have started to close.",
                "The long breath out then removes more carbon dioxide in one cycle.",
                "A mouth breath out may feel more like a sigh, but using the nose works too.",
            ],
        ),
        evidence: bullets(
            "The body process is well understood, but research on one or two sighs is still new.",
            &[
                "A 2023 trial tested five minutes a day, not this quick reset.",
                "A 2026 pilot found that about a minute helped during real anxiety moments.",
                "Box breathing worked just as well, so the pilot did not show that sighing was special.",
            ],
        ),
        evidence_grade: EvidenceGrade::Moderate,
        safety_note: "",
        preparation: prose(""),
        goal: TechniqueGoal::Reset,
        stages: &[stage(
            // Two consecutive INHALE phases, deliberately. The second sip
            // re-inflates collapsed alveoli and is a distinct beat the client
            // cues separately; merging them into one long inhale loses the
            // technique. The sip stays the smaller of the pair and long enough
            // that the cue announcing it lands before the phase is over.
            &[
                // 250 is the motor turn between a full breath and finding
                // more on top of it. The zero after the sip is the technique
                // itself: you top up and you let go, without a pause between.
                inhale(Passage::Nose, 1500, (1000, 2500)).with_gap(250),
                inhale(Passage::Nose, 1000, (500, 1200))
                    .with_gap(0)
                    .with_haptic(HapticPattern::Sip),
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
    // `physiological-sigh`, because an occasion sets the minutes and nothing
    // else. The trial dosed a slower cycle with a longer first breath, not five
    // minutes of the sigh (`docs/product/breathing-science.md` §3.6), and
    // different phase durations mean a different technique.
    TechniqueSeed {
        slug: "cyclic-sighing",
        name: "Cyclic Sighing",
        summary: "Five minutes of soft, repeated sighs can turn a quick reset into a calm daily practice.",
        mechanism: bullets(
            "Cyclic sighing combines the release of a sigh with the steady pace of a five-minute daily practice.",
            &[
                "Each second sip helps reopen small air sacs before the long breath out.",
                "Ten-second cycles give you six breaths per minute, a pace often used in slow-breathing research.",
                "A mouth breath out may feel more natural, but using the nose works too.",
            ],
        ),
        evidence: bullets(
            "One promising month-long trial supports this practice, but it has not yet been repeated.",
            &[
                "In 2023, five daily minutes improved mood and resting breathing rate more than three comparison practices.",
                "The trial had about 30 people per group and came from one laboratory.",
                "Later short-dose studies were mixed, and one found box breathing worked just as well.",
            ],
        ),
        evidence_grade: EvidenceGrade::Moderate,
        safety_note: "",
        preparation: prose(""),
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            // Two consecutive inhales for the same reason as the physiological
            // sigh's, at different lengths deliberately: the two must not draw
            // or speak as one figure, and the longer first breath is what makes
            // five minutes of this sustainable. The sip's 0.5s floor is the
            // watch haptic floor, matching the sigh.
            &[
                inhale(Passage::Nose, 2000, (1500, 3000)).with_gap(250),
                inhale(Passage::Nose, 1000, (500, 1500))
                    .with_gap(0)
                    .with_haptic(HapticPattern::Sip),
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
    // A technique rather than an occasion override, for the one thing an
    // override cannot reach: a route may replace the rhythm but never the
    // passage, and the mouth is what this exercise is.
    TechniqueSeed {
        slug: "pursed-lip-breathing",
        name: "Pursed-Lip Breathing",
        summary: "A gentle breath out through pursed lips can help you recover when you are already short of breath.",
        mechanism: bullets(
            "Pursed-Lip Breathing can make each breath feel more effective by keeping small airways open for longer.",
            &[
                "The narrow opening at your lips creates gentle pressure as you breathe out.",
                "That pressure can help trapped air leave before the next breath in.",
                "Let the air move steadily rather than blowing hard. The slower breath out is the useful part.",
            ],
        ),
        evidence: bullets(
            "This is common in lung care, but the average benefit is small.",
            &[
                "A 2024 review of 73 trials found less breathlessness, but the change was too small for most patients to notice.",
                "Another review found that people walked farther, but exercise training worked just as well.",
                "Healthy people are rarely studied, so claims about general calm are uncertain.",
            ],
        ),
        evidence_grade: EvidenceGrade::Moderate,
        safety_note: "",
        preparation: prose(
            "Part your lips gently, as though you were about to whistle or cool a spoonful of soup.",
        ),
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            &[
                // 200 is purse time. The exhale's turn is the ordinary one, so
                // it is derived: pursed lips are already shaped by then.
                inhale(Passage::Nose, 2000, (2000, 4000)).with_gap(200),
                shaped_exhale(Passage::Mouth, Manner::PursedLips, 4000, (4000, 8000))
                    .with_haptic(HapticPattern::Press),
            ],
            // Not a sitting, so not the five minutes one opens on: this is a
            // recovery taken standing up, and the cycle dial reaches down to
            // the ten breaths somebody uses halfway up a flight of stairs.
            30,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "humming-breath",
        name: "Humming Breath",
        summary: "A steady hum on each long breath out can make slow nasal breathing feel grounded and absorbing.",
        mechanism: bullets(
            "Humming Breath can give a slow rhythm a soothing sound and a physical vibration you can follow.",
            &[
                "Humming makes the air in the nose and sinuses vibrate.",
                "It briefly raises nitric oxide in the nose, which helps regulate airflow and blood vessels.",
                "The hum naturally keeps the breath out slow and nasal without extra counting.",
            ],
        ),
        evidence: bullets(
            "The effect on nasal nitric oxide is well established; the wider wellbeing claims are less certain.",
            &[
                "Several small trials report less anxiety or better sleep after humming practices.",
                "The studies cannot separate the hum from the slow nasal breathing beneath it.",
                "Claims that humming clears sinus infections rely mainly on a single case report.",
            ],
        ),
        evidence_grade: EvidenceGrade::Limited,
        safety_note: "",
        preparation: prose(
            "Choose somewhere you do not mind making a low sound; neither pitch nor volume matters.",
        ),
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            &[
                // 150 to find the note. 200 because a throat that has hummed
                // for eight seconds does not inhale on the beat.
                inhale(Passage::Nose, 4000, (3000, 6000)).with_gap(150),
                // The hum runs the length of the exhale, so the dial reaches
                // fifteen seconds, the widest exhale in the catalogue.
                // `user_technique::repository::phase_limits` takes the widest
                // of each kind as what anybody may author, so this raises the
                // authored exhale ceiling from twelve seconds to fifteen.
                shaped_exhale(Passage::Nose, Manner::Hum, 8000, (6000, 15000))
                    .with_gap(200)
                    .with_haptic(HapticPattern::Press),
            ],
            // The five minutes a sitting opens on, at twelve seconds a cycle.
            // Nothing about a hum argues for an exception.
            25,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
    // The catalogue's only mouth inhale, which is why it is a technique rather
    // than a rhythm an occasion could prescribe: an override may re-time the
    // breaths it borrows and never move the air somewhere else.
    TechniqueSeed {
        slug: "cooling-breath",
        name: "Cooling Breath",
        summary: "A gentle mouth breath in and nasal breath out can feel refreshing when heat makes it hard to settle.",
        // The shapes themselves moved to `preparation`, which is read in the
        // settling beat and sits directly above this on the exercise's own
        // screen. Saying them twice, adjacently, is what that field is for
        // avoiding — so this explains and the sentence above instructs.
        mechanism: bullets(
            "Cooling Breath can create a refreshing sensation by drawing air slowly across the moisture in your mouth.",
            &[
                "A curled tongue or gently closed teeth can both create the cooling airflow.",
                "Breathing out through the nose returns you to a slow, comfortable rhythm.",
                "Choose another exercise in cold or polluted air, or if cool air makes your chest feel tight.",
            ],
        ),
        evidence: bullets(
            "Research is limited, especially on whether the exercise cools more than your mouth.",
            &[
                "One unblinded trial of about 100 people tracked blood pressure and heart rate variability (HRV) for three months.",
                "No controlled study has shown that it cools the whole body.",
                "The safest claim is that many people enjoy the airflow in warm weather.",
            ],
        ),
        evidence_grade: EvidenceGrade::Limited,
        // No note, on humming breath's reasoning: the caution here is cold or
        // polluted air, which is a reason to pick another exercise today rather
        // than something that can hurt somebody mid-breath, so it rides the
        // mechanism prose instead of the phone's full-screen warning.
        safety_note: "",
        // The alternative is the point, not a footnote to it: a tongue that will
        // not roll is common, and the cue beside each breath can only name the
        // curl. Whoever cannot make that shape reads the answer here or nowhere.
        preparation: bullets(
            "Choose the shape that feels natural.",
            &[
                "Curl your tongue into a loose tube.",
                "If your tongue does not roll, close your teeth gently and draw the air in over them.",
            ],
        ),
        goal: TechniqueGoal::Calm,
        stages: &[stage(
            &[
                // Two mechanical changes a cycle, tongue and mouth, so both
                // turns are authored and at the same length.
                shaped_inhale(Passage::Mouth, Manner::CurledTongue, 4000, (3000, 6000))
                    .with_gap(200),
                exhale(Passage::Nose, 6000, (4000, 8000)).with_gap(200),
            ],
            // Five minutes at ten seconds a cycle — the sitting the catalogue
            // opens on. Nothing about a cooling breath argues for an exception.
            30,
        )],
        recommended_rounds: 1,
        requires_subscription: false,
    },
    TechniqueSeed {
        slug: "bellows-breath",
        name: "Bellows Breath",
        summary: "A short round of quick nose breathing can give you a sharp lift in energy and focus.",
        mechanism: bullets(
            "Bellows Breath can create a quick, bright sense of energy by copying the breathing pattern of exertion.",
            &[
                "Fast, forceful breathing can raise heart rate and adrenaline.",
                "It also lowers carbon dioxide quickly, which can cause tingling or lightheadedness.",
                "Keep the bout brief and stay seated. Continuing longer adds risk without adding energy.",
            ],
        ),
        evidence: bullets(
            "Small studies suggest a short lift in alertness, but we do not know how large it is.",
            &[
                "Trials with a few dozen people found changes in heart rate, alertness and reaction time.",
                "The studies were not blinded and mainly tested traditional fast breathing.",
                "Research has not compared it with simple options, such as standing up or taking a short walk.",
            ],
        ),
        evidence_grade: EvidenceGrade::Limited,
        preparation: prose(""),
        safety_note: "Sitting down only. Stop at the first sign of lightheadedness. Never in \
                      water, never while driving.",
        goal: TechniqueGoal::Energy,
        stages: &[stage(
            &[
                // Thirty breaths a minute, with continuity as the technique.
                inhale(Passage::Nose, 1000, (700, 1500)).continuous(),
                exhale(Passage::Nose, 1000, (700, 1500)).continuous(),
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
        summary: "Three rounds of fast breathing and gentle holds can feel intense and focused when done safely.",
        mechanism: bullets(
            "Wim Hof-style rounds can feel vivid and absorbing because fast breathing changes the signals that normally end a breath hold.",
            &[
                "Thirty quick breaths lower carbon dioxide, which delays the urge to breathe.",
                "The same fast pace can raise adrenaline and cause a bright or tingling sensation.",
                "End every hold while it is still comfortable. A longer hold is not a better result.",
            ],
        ),
        evidence: bullets(
            "People report a strong effect, but trials have not found clear health or mood benefits.",
            &[
                "A blinded study of about 200 people found no clear change in stress, mood or inflammation, and more side effects.",
                "A study of 84 women found that this method plus cold exposure was no better than a gentler comparison.",
                "We do not know whether fast breathing and holds cause any wider benefit.",
            ],
        ),
        evidence_grade: EvidenceGrade::Limited,
        preparation: prose(""),
        safety_note: "Sitting or lying down, always. Never in water, never in the bath, never \
                      driving or standing. Fast breathing can make you faint with no warning. \
                      Tingling in the hands and face is ordinary; dizziness means stop. Never \
                      push a hold to the limit. This app does not measure one.",
        goal: TechniqueGoal::Energy,
        stages: &[
            stage(
                &[
                    // Bellows at a slower count, and the same cadence for it.
                    inhale(Passage::Nose, 1500, (1000, 2500)).continuous(),
                    exhale(Passage::Nose, 1500, (1000, 2500)).continuous(),
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
            // it. Alone in its stage because open-endedness is a property of
            // the stage: any phase sharing it would wait for a tap nothing asks
            // for. The duration is the first round's aim and the session grows
            // it by that much each round — a suggestion, never a requirement.
            open_ended_stage(&[
                // The zero states what an open-ended stage already does: it has
                // no next boundary to turn on. You breathe when you need to.
                hold_out(30000, (30000, 120_000))
                    .with_gap(0)
                    .with_haptic(HapticPattern::LongHold),
            ]),
            stage(
                &[
                    // The recovery breath runs straight into its hold. The
                    // reminder tap is for the dial: at the seeded fifteen
                    // seconds the hold ends before the first one is due.
                    inhale(Passage::Nose, 3000, (2000, 5000)).with_gap(0),
                    hold_in(15000, (10000, 20000))
                        .with_gap(150)
                        .with_haptic(HapticPattern::LongHold),
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
        summary: "Longer counts make box breathing a calm way to focus before work.",
        mechanism: bullets(
            "Long Box Breathing can help gather your attention by making every side of the pattern deliberate.",
            &[
                "Six-count sides are long enough to need gentle attention rather than habit.",
                "The pauses give a wandering mind a clear count to return to.",
                "The slow, even rhythm can keep that concentration calm rather than tense.",
            ],
        ),
        evidence: bullets(
            "No trial has tested this longer pattern, so the focus benefit is based on experience.",
            &[
                "Slow-breathing research supports the calm rhythm underneath it.",
                "No study has compared six-count sides with four-count box breathing.",
                "Treat the focus effect as how it may feel, not a proven change in attention.",
            ],
        ),
        evidence_grade: EvidenceGrade::Limited,
        safety_note: "",
        preparation: prose(""),
        goal: TechniqueGoal::Focus,
        stages: &[stage(
            &[
                inhale(Passage::Nose, 6000, (4000, 10000)),
                // Box breathing's turns, unchanged: the same body leaves a
                // longer hold, so a longer square does not widen them.
                hold_in(6000, (4000, 10000)).with_gap(150),
                exhale(Passage::Nose, 6000, (4000, 10000)),
                hold_out(6000, (4000, 10000)).with_gap(120),
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
        summary: "Slow breaths from side to side can settle you and focus your mind before work.",
        mechanism: bullets(
            "Alternate-Nostril Breathing can feel both calming and absorbing because each breath asks for a simple hand movement.",
            &[
                "Switching sides keeps your attention close to the breath.",
                "The slow nasal rhythm supports the same settling response as other slow exercises.",
                "After a few minutes, the sequence can become steady enough to carry into the task ahead.",
            ],
        ),
        evidence: bullets(
            "Studies exist, but their mixed results do not support a firm claim.",
            &[
                "A 2024 review found lower blood pressure, but the trials differed widely.",
                "Small anxiety studies found little or no help when people used it for quick relief.",
                "No study has separated nostril switching from the slow breath and focus around it.",
            ],
        ),
        evidence_grade: EvidenceGrade::Limited,
        safety_note: "",
        // The one preparation line whose technique has no manner. Which finger
        // seals which nostril never changes across fifteen cycles, so it belongs
        // where a constant is read once rather than on the line that alternates.
        preparation: numbered(
            "Set your right hand comfortably before you begin.",
            &[
                "Rest your thumb beside your right nostril.",
                "Rest your ring finger beside your left nostril.",
            ],
        ),
        goal: TechniqueGoal::Focus,
        stages: &[stage(
            &[
                // The gaps encode the hand: 300 where the fingers move to a
                // new nostril, 0 where the nostril is already open.
                inhale(Passage::LeftNostril, 4000, (3000, 6000)).with_gap(300),
                exhale(Passage::RightNostril, 6000, (4000, 8000)).with_gap(0),
                inhale(Passage::RightNostril, 4000, (3000, 6000)).with_gap(300),
                exhale(Passage::LeftNostril, 6000, (4000, 8000)).with_gap(0),
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

/// Array order is reading order. Practice leads, then the refinements, the
/// higher-care practices, the uncertain dose, and the boundary of what the
/// evidence and the app can claim. `docs/product/breathing-foundations.md` is
/// the claim-by-claim ledger every answer here is answerable to, and it moves
/// in the same commit as this list.
pub(super) const FOUNDATIONS: &[FoundationSeed] = &[
    FoundationSeed {
        slug: "what-matters-most",
        question: "How exact does it need to be?",
        answer: bullets(
            "A comfortable exercise you repeat is more useful than a perfect pattern you avoid.",
            &[
                "Choose a well-studied exercise that feels easy enough to return to.",
                "Nose breathing, belly movement and exact counts are refinements you can add later.",
                "Treat fast breathing and long holds with extra care.",
            ],
        ),
    },
    FoundationSeed {
        slug: "what-a-good-breath-feels-like",
        question: "What should a good breath feel like?",
        answer: bullets(
            "A good breath feels quiet and comfortable. It does not need to be large.",
            &[
                "Let your ribs and belly move without forcing them.",
                "Make the breath smaller if you feel air hunger, tingling or dizziness.",
                "Stop if those feelings do not settle.",
            ],
        ),
    },
    FoundationSeed {
        slug: "is-a-deep-breath-the-answer",
        question: "Is a deep breath always the answer?",
        answer: bullets(
            "No. A very large breath can make dizziness and air hunger worse when panic is rising.",
            &[
                "Try a smaller, quieter breath instead.",
                "Slow down only as far as feels comfortable.",
                "Breathing practice may support you, but it is not treatment for panic.",
            ],
        ),
    },
    FoundationSeed {
        slug: "why-it-works",
        question: "Why can slow breathing help?",
        answer: bullets(
            "Slow breathing supports the body systems that settle you.",
            &[
                "Your heart speeds up as you breathe in and slows as you breathe out.",
                "A slower cycle increases heart rate variability (HRV) while you practise.",
                "Many people feel calmer, but the effect is usually small.",
            ],
        ),
    },
    FoundationSeed {
        slug: "belly-or-chest",
        question: "Belly or chest?",
        answer: prose(
            "Let the breath move low if that feels easy. A hand below your ribs can help you notice the diaphragm working. Chest movement is not a mistake, and you never need to force your belly out.",
        ),
    },
    FoundationSeed {
        slug: "nose-or-mouth",
        question: "Nose or mouth?",
        answer: bullets(
            "Use your nose when it is comfortable, and use your mouth when it is not.",
            &[
                "Your nose filters, warms and moistens the air.",
                "Its gentle resistance can make the breath easier to slow.",
                "Nasal breathing does not add oxygen, and its wider benefits for healthy people remain uncertain.",
            ],
        ),
    },
    FoundationSeed {
        slug: "how-slow",
        question: "How slow?",
        answer: prose(
            "Aim for slower than usual without straining. Five or six breaths per minute is the pace most often used in research. Shorten the count or breathe normally if the guide leaves you short of air.",
        ),
    },
    FoundationSeed {
        slug: "fast-breathing-and-holds",
        question: "What about fast breathing and holds?",
        answer: bullets(
            "Fast breathing and holds are optional, not more advanced versions of slow breathing.",
            &[
                "Fast breathing can lower carbon dioxide and cause tingling, dizziness or fainting.",
                "Practise it seated or lying down, never while driving or near water.",
                "Keep holds comfortable and skip them if you finish gasping.",
            ],
        ),
    },
    FoundationSeed {
        slug: "getting-comfortable",
        question: "How should I get comfortable?",
        answer: bullets(
            "Choose a position that suits the session.",
            &[
                "Sit to stay alert; lie down when preparing for sleep.",
                "Keep your posture easy rather than rigid, with your eyes open or closed.",
                "Follow the guide instead of the feeling if attention on your breath is uncomfortable, and stop early if needed.",
            ],
        ),
    },
    FoundationSeed {
        slug: "how-long",
        question: "How long and how often?",
        answer: bullets(
            "Start with a length you can repeat comfortably. A longer session is not automatically better.",
            &[
                "One minute may help with a momentary spike.",
                "Studies of change over time often use five-to-ten-minute sessions on most days.",
                "Research has not settled on one best dose.",
            ],
        ),
    },
    FoundationSeed {
        slug: "when-breathing-is-the-problem",
        question: "When breathing itself is the problem",
        answer: prose(
            "Some people cannot get a breath that feels satisfying, even with healthy lungs. Frequent sighing, a tight chest or never feeling full can be part of this common and treatable breathing pattern.",
        ),
    },
    FoundationSeed {
        slug: "how-good-is-the-evidence",
        question: "How good is the evidence?",
        answer: bullets(
            "The evidence is promising, modest and uneven.",
            &[
                "Trials find small to medium improvements in stress and anxiety, but many studies are small or at risk of bias.",
                "Slow breathing reliably changes heart rate variability (HRV) during practice; lasting benefits are less certain.",
                "No single pattern has proved best, and breathing practice should sit alongside medical treatment rather than replace it.",
            ],
        ),
    },
    FoundationSeed {
        slug: "why-no-scores",
        question: "Why doesn't önd score you?",
        answer: bullets(
            "A breathing number describes one measurement, taken once.",
            &[
                "Comfortable-pause targets, coherence scores and breathing ages are not established measures of improvement.",
                "önd records what you practised, for how long, and how it felt.",
                "Your resting breathing rate is compared only with your own earlier measurements.",
            ],
        ),
    },
];

/// The occasion entries: why somebody opened the app, and where that routes.
/// Array order is presentation order, as in [`TECHNIQUES`]. Two pairs are
/// authored as pairs, sharing a technique, a goal and a duration and differing
/// only in surface: `through-this-meeting` with `after-a-hard-meeting`, and
/// `awake-at-3am` with `winding-down`. Other matches are coincidence.
pub(super) const OCCASIONS: &[OccasionSeed] = &[
    OccasionSeed {
        slug: "five-minutes-today",
        name: "Five minutes today",
        summary: "Build the regular five-minute habit that the strongest daily-practice evidence supports.",
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
        slug: "ten-quiet-minutes",
        name: "Ten quiet minutes",
        summary: "Follow a smooth, count-free rhythm for ten quiet minutes.",
        technique_slug: "coherent-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        // Ten minutes, at the top of the five-to-twenty band the multi-week
        // trials cluster in — the length, and only the length, is what makes
        // this a second door beside the entry above rather than a rival to it.
        duration_ms: 600_000,
    },
    OccasionSeed {
        slug: "before-a-presentation",
        name: "Before a presentation",
        summary: "Steady your breathing and gather your attention before you walk in.",
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
        summary: "Let your body settle before the next part of the day begins.",
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
        summary: "Keep a quiet settling rhythm going with no screen to watch and nothing to hear.",
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
        summary: "Ease your breathing towards a slower rhythm once the hard work is over.",
        // An out-breath longer than the in-breath, rather than coherent
        // breathing's fixed rate. Straight off hard cardio the drive to breathe
        // is still elevated while CO₂ clears, so a fixed rate would ask somebody
        // to underbreathe through it. A ratio works at whatever rate they arrive
        // at.
        technique_slug: "extended-exhale",
        // Borrowed rather than inherited, and the first entry where that
        // distinction did any work: the technique is grouped under sleep, and
        // coming down from a session is not going to bed. Every daytime route
        // onto this exercise since borrows the same way.
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
        slug: "when-youre-winded",
        name: "When you're winded",
        summary: "Use gentle breaths out through pursed lips to help your breathing settle.",
        technique_slug: "pursed-lip-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        // Here rather than on the exercise because the hazard is the moment:
        // somebody practising on a calm afternoon needs the first sentence and
        // none of the second.
        safety_note: "Practise this while you are comfortable rather than meeting it for the \
                      first time out of breath. A shape you already know is far easier to find. \
                      Breathlessness that is new, that is severe, or that is not settling is a \
                      matter for a doctor rather than an app, and breathlessness that arrives \
                      suddenly or alongside chest pain is a matter for an emergency number.",
        // Two minutes rather than the exercise's own three: somebody out of
        // breath is counting this in breaths until they can talk again, and the
        // offer should not ask for longer than that.
        duration_ms: 120_000,
    },
    OccasionSeed {
        slug: "when-you-cant-get-a-satisfying-breath",
        name: "When you can't get a satisfying breath",
        summary: "A small, even rhythm can help when you keep reaching for a bigger breath that never feels complete.",
        technique_slug: "extended-exhale",
        // Calm rather than the exercise's own sleep: this arrives in the middle
        // of somebody's day and reaching for a bigger breath is not a bedtime
        // problem.
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        // Here rather than on the exercise, on `when-youre-winded`'s reasoning:
        // somebody breathing an extended exhale on an ordinary evening needs
        // none of this. The red-flag sentence is word for word that route's,
        // deliberately — two moments, one piece of clinical advice, and a
        // reworded copy of it would be a second answer to the same question.
        safety_note: "A breath that will not satisfy is common, and most of the time nothing \
                      serious is behind it. Breathlessness that is new, that is severe, or that is \
                      not settling is a matter for a doctor rather than an app, and breathlessness \
                      that arrives suddenly or alongside chest pain is a matter for an emergency \
                      number.",
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "when-panic-is-rising",
        name: "When panic is rising",
        summary: "Small, quiet breaths, not deep ones, can help you step out of the cycle of taking ever-larger breaths as panic rises.",
        // Extended exhale rather than the sigh `a-moment-to-reset` routes to.
        // That pattern stacks a second inhale on the first, which is the one
        // shape to keep away from somebody whose problem is already
        // over-breathing — so a spike and a rising panic want different doors,
        // and this is the second one.
        technique_slug: "extended-exhale",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        // About nine breaths a minute with deliberately small breaths, which is
        // the pace the panic-adjacent trials ran. Both phases sit under Extended
        // Exhale's own floors: the rhythm belongs to this moment, not to the
        // exercise somebody starts on a calm evening.
        phase_durations_ms: &[2500, 4500],
        // Deliberately empty. The phone renders an occasion's note as a
        // full-screen warning before the countdown, and a warning is the last
        // thing to put in front of somebody who tapped this — the caveats that
        // belong here are in the summary, where they are read before the tap
        // rather than in the way of it.
        safety_note: "",
        duration_ms: 180_000,
    },
    OccasionSeed {
        slug: "in-a-tight-spot",
        name: "In a tight spot",
        summary: "Use a discreet slow rhythm to create a little more room in a scanner, lift or crowded journey.",
        technique_slug: "extended-exhale",
        goal: TechniqueGoal::Calm,
        // Discreet because the moment is: somebody inside a scanner cannot hold
        // a lit phone, and somebody on a packed train would rather nobody saw.
        surface: DeliverySurface::Discreet,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "overloaded-and-need-quiet",
        name: "Overloaded and need quiet",
        summary: "Four quiet, even counts give you one predictable thing to follow when everything feels like too much.",
        // Box rather than a ratio, and this is the one route where that choice
        // is the prescription: a fixed symmetric count is the most predictable
        // shape the catalogue has, and predictability is the only thing the
        // relevant literature supports. The moment is stated as a state and
        // never as a population — no route in this file names who is having it.
        technique_slug: "box-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::Discreet,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        // Three minutes, and identical to `before-a-presentation` apart from the
        // surface by coincidence rather than by authorship — two moments wanting
        // the same box for the same three minutes. Not a pair, and deliberately
        // not enrolled in `every_surface_pair_differs_only_in_its_surface`:
        // pinning it would freeze two doses that were curated apart.
        duration_ms: 180_000,
    },
    OccasionSeed {
        slug: "feeling-queasy",
        name: "Feeling queasy",
        summary: "Slow, even breathing may make nausea a little easier to ride out while it passes.",
        // Coherent breathing rather than the extended exhale the routes above
        // take. The nausea trials paced people at a fixed slow rate with nothing
        // to count, which is this exercise; a ratio to hold on to is more to ask
        // of somebody trying not to be sick.
        technique_slug: "coherent-breathing",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::Discreet,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        // Roughly the length the nausea trials measured, and about as long as
        // anybody feeling sick will keep going.
        duration_ms: 180_000,
    },
    OccasionSeed {
        slug: "winding-down",
        name: "Winding down",
        summary: "Use long, slow breaths out to settle at the end of the day.",
        technique_slug: "extended-exhale",
        goal: TechniqueGoal::Sleep,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "awake-at-3am",
        name: "Awake at 3am",
        summary: "Follow long, slow breaths out in the dark without waking yourself further with a screen.",
        technique_slug: "extended-exhale",
        goal: TechniqueGoal::Sleep,
        // At three in the morning a lit screen is the thing keeping somebody
        // awake, and they are already lying down — which is also what lists
        // this one on the watch, the only device already within reach.
        surface: DeliverySurface::Discreet,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        duration_ms: 300_000,
    },
    OccasionSeed {
        slug: "with-your-child",
        name: "With your child",
        summary: "Share a short, playful breathing rhythm that a small child can follow with you.",
        technique_slug: "extended-exhale",
        goal: TechniqueGoal::Calm,
        surface: DeliverySurface::FullScreen,
        register: CopyRegister::Playful,
        // This rhythm belongs to doing the exercise with a child, not to
        // Extended Exhale as a standalone exercise.
        phase_durations_ms: &[3000, 5000],
        safety_note: "This is for breathing alongside a child, not for teaching one to hold \
                      their breath. There are no holds here and none should be added. \
                      Breath-holding and fast breathing are not for children. Stop if they feel \
                      dizzy, or if they have stopped enjoying it.",
        // Ninety seconds — eleven cycles of the eight-second rhythm. Long enough
        // to settle, short enough to finish before a child is finished with it.
        duration_ms: 90_000,
    },
    OccasionSeed {
        slug: "a-moment-to-reset",
        name: "A moment to reset",
        summary: "Use one quiet minute of sighs to take the edge off a sudden spike wherever you are.",
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
    OccasionSeed {
        slug: "riding-out-a-craving",
        name: "Riding out a craving",
        summary: "A few slow minutes can help take the edge off a craving while its peak passes.",
        technique_slug: "extended-exhale",
        // Reset rather than calm: a craving is a spike to be outlasted, and the
        // entry belongs beside the moment-to-reset it sits under rather than
        // among the sittings.
        goal: TechniqueGoal::Reset,
        surface: DeliverySurface::Discreet,
        register: CopyRegister::Plain,
        phase_durations_ms: &[],
        safety_note: "",
        // The length the craving trials ran, and about how long a craving peak
        // lasts.
        duration_ms: 180_000,
    },
];

/// The Start here progression: a curated order over part of the catalogue, for
/// somebody who has not picked a goal at all (TIM-60, D2). Array order is the
/// ordering and the index is the `ordinal`. Suggestive and never gating —
/// nothing reads this list to decide what somebody may breathe, and the
/// techniques it leaves out stay listed, described and playable.
pub(super) const PROGRESSION: &[ProgressionStepSeed] = &[
    ProgressionStepSeed {
        technique_slug: "box-breathing",
        note: "Start with four even counts, which are simple to follow on your first try.",
    },
    ProgressionStepSeed {
        technique_slug: "physiological-sigh",
        note: "Next, learn a quick reset for the moments when you cannot give five minutes.",
    },
    ProgressionStepSeed {
        technique_slug: "cyclic-sighing",
        note: "Then turn the same sigh into a five-minute daily practice.",
    },
    ProgressionStepSeed {
        technique_slug: "extended-exhale",
        note: "Then try a slow rhythm you can use lying down, with no hold to manage.",
    },
    ProgressionStepSeed {
        technique_slug: "coherent-breathing",
        note: "Finish with a smooth, count-free pace you can settle into for longer.",
    },
];
