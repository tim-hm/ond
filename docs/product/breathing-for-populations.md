# Breathing for ADHD, perimenopause and athletes

What the evidence actually supports for the three populations önd keeps reaching for, what each one maps onto in the catalogue we already have, and draft words for saying so.

This is research input, not shipped copy. TIM-19 routes on it, TIM-28 writes from it, and every block marked **Draft** below is a proposal for Tim to cut, not a decision.

## Why this document exists before the copy does

The positioning claim is that a breathing app answering a specific situation beats one offering five abstract nouns. That claim is worth making only if the specific answer is different from the general one. So the question this document asks of each population is not "does breathing help these people" — it is **"does the evidence support telling them something we would not tell everybody else?"**

For one of the three the honest answer turns out to be no, and for the population where the answer is closest to yes the strongest evidence is for an intervention this app cannot deliver. Both are written up as found.

## The line

önd is a wellness product. Nothing here proposes a treatment claim, an implied diagnosis, or a sentence of the form "helps with X". The register to match already exists in the product:

- The safety consent says "önd is not medical advice" and names the conditions worth a doctor's opinion first (`SafetyConsent.current` in `ios/Packages/OndCore/Sources/OndKit/SafetyConsent.swift`).
- The privacy page says of the coach: "It is not a doctor, it does not diagnose, and nothing it says is medical advice."
- The catalogue already writes its own evidence down honestly — Wim Hof-style rounds are described as "thinner on trial evidence than its reputation suggests", alternate-nostril as having "modest trial support".

That last habit is the one to keep. The catalogue is willing to tell you an exercise is less proven than you think. A population layer that stops doing that in order to sound personal would be a worse product, not a more personal one.

## The baseline everyone already gets

Populations have to be measured against something, and the something is the general effect. The best current pooled estimate for breathwork on self-reported stress in adults is a small-to-medium one: g = −0.35, 95% CI [−0.55, −0.14], across 12 randomised-controlled trials and 785 participants, with most studies at moderate risk of bias ([Fincham et al. 2023, _Scientific Reports_](https://www.nature.com/articles/s41598-022-27247-y)).

That is a real effect and it is what the marketing page already claims. It is also the number every population section below is competing with. "This helps you the way it helps everybody" is a true sentence. "This helps you _because_ you are X" needs its own evidence, and mostly does not have it.

## ADHD

### Arriving with ADHD

"I have ADHD and I struggle to settle." "I can't sit still for a meditation app." "My brain won't stop."

### Evidence: preliminary at best, and none of it is about breathing

There is no randomised trial of a breathing technique as a standalone intervention in ADHD worth building copy on. What exists sits one step away and points sideways.

**Meditation-based mind-body interventions, pooled.** A meta-analysis of randomised controlled trials of mindfulness, yoga, tai chi and qigong in people with ADHD found small effects: inattention g = −0.26, hyperactivity/impulsivity g = −0.19, executive function g = −0.35 ([Zhang et al. 2023, _Journal of Attention Disorders_](https://pubmed.ncbi.nlm.nih.gov/36803119/)). Three caveats matter more than the numbers. The interventions are multi-component, so no part of that effect is attributable to breathing. None of the trials blinded participants or therapists, which for a subjective-outcome, self-selected-adherence intervention is the failure mode that inflates effects. And the comparison is usually inactive control rather than an equally plausible activity.

**Guidelines.** NICE NG87 recommends structured psychological intervention and CBT elements for adults who have chosen not to take medication; standalone mindfulness is not recommended for controlling core ADHD symptoms on current evidence ([NICE NG87](https://www.nice.org.uk/guidance/ng87/chapter/recommendations)).

**Autonomic mechanism.** People with ADHD show reduced vagally-mediated heart rate variability during cognitive tasks, at a small effect size, across 13 studies, 869 participants with ADHD and 909 controls; resting-state differences are weaker and less consistent ([Robe et al. 2019, _Neuroscience & Biobehavioral Reviews_](https://www.sciencedirect.com/science/article/abs/pii/S0149763418308005)). This is a plausible mechanism and nothing more. A physiological difference at baseline is not evidence that an intervention which moves that physiology changes anything a person cares about.

**Verdict.** Preliminary, indirect, unblinded. önd may not say breathing helps ADHD, and should not imply it by arrangement either — putting a technique under a heading that says ADHD is a claim whether or not the sentence beneath it makes one.

### The finding that changes the product, not the copy

The obvious mapping is ADHD to `TECHNIQUE_GOAL_FOCUS`, on the strength of the word. It is the wrong one.

The two focus techniques are the two highest-executive-load exercises in the catalogue. Long Box Breathing runs four counted sides — its own summary says "there is enough to keep track of that there is no room left to drift". Alternate-Nostril Breathing adds hand choreography to a four-beat asymmetric sequence. Routing on the word "focus" would hand somebody who has just told us they struggle to hold a sequence in mind the two exercises that most demand it, and would do it while presenting itself as tailored.

The techniques that ask least are Box Breathing (one number, four times) and the Physiological Sigh (three beats, over in seconds). Neither is a focus technique. Both are free, which for a population that abandons paid wellness apps at the first friction is not a small detail.

### Where ADHD lands in the catalogue

| Route                      | Resolves to                                         | Why                                                                                          |
| :------------------------- | :-------------------------------------------------- | :------------------------------------------------------------------------------------------- |
| Primary                    | `box-breathing` (`CALM`)                            | Lowest cognitive load in the catalogue, no subscription, works first try                     |
| Second                     | `physiological-sigh` (`RESET`)                      | Seconds rather than minutes — the only honest answer to "I can't sit still for five minutes" |
| The existing route         | The **Start here** progression                      | Its first two steps are already exactly those two techniques, in that order                  |
| Not recommended by default | `long-box-breathing`, `alternate-nostril` (`FOCUS`) | Highest executive load; listed and playable as always, never surfaced first                  |

The third row is the useful one for TIM-19. "I have ADHD" does not need a population route at all — it lands on the ordering `PROGRESSION` already encodes, for reasons that have nothing to do with ADHD and everything to do with load. The right response to this population is the response we built for beginners.

### Draft copy for ADHD

> **Draft, for Tim's review.**
>
> On routing (shown after the note is typed):
>
> "Short and simple first, then. Box breathing is four counts of four — one number, nothing to keep track of, and it works the first time. If five minutes is too long a promise today, the Physiological Sigh takes about twenty seconds."
>
> Coach framing, appended to the prompt rather than shown:
>
> "They have described difficulty settling and sustaining attention. Prefer short sessions, one instruction at a time, and techniques with a single count. Do not comment on the diagnosis, do not offer it advice, and never suggest breathing as a treatment for it."
>
> What we will not say: "breathing exercises help ADHD"; "improves focus and attention"; anything naming the diagnosis back at the person as though we had verified it.

## Perimenopause

### Arriving perimenopausal

"I'm perimenopausal and waking at 3am." "The hot flushes are relentless." "I'm anxious in a way I never used to be."

### Evidence: strong, and it points the other way

This is the finding that matters most in this document.

Paced breathing for hot flushes and night sweats is not merely unproven. It has been tested properly, it failed, and the professional body has ruled against it. The Menopause Society's 2023 nonhormone therapy position statement classifies **paced respiration as "not recommended" at Level I evidence** — its highest evidence grade, meaning good and consistent scientific evidence. The statement's own wording is that "paced breathing and relaxation techniques do not alleviate VMS and are not recommended" ([The Menopause Society 2023 nonhormone therapy position statement, _Menopause_ 30(6):573–590](https://pubmed.ncbi.nlm.nih.gov/37252752/); [recommendation table](https://www.guidelinecentral.com/guideline/9842/)).

The two trials behind that grade are worth knowing individually, because their shape is instructive.

**Carpenter et al. 2013.** A 16-week, three-arm, partially blinded controlled trial, 218 women randomised (96 breast cancer survivors, 122 without cancer), comparing paced respiration against a fast-shallow-breathing active control and usual care. No significant group differences on the primary outcomes at 8 or 16 weeks. Most intervention participants did not reach a 50% reduction in vasomotor symptoms **despite demonstrating that they could perform the technique correctly and practising daily**. The authors' conclusion: "Paced respiration is unlikely to provide clinical benefit for vasomotor or other menopausal symptoms" ([_J Gen Intern Med_ 28(2):193–200](https://pmc.ncbi.nlm.nih.gov/articles/PMC3614127)).

That parenthesis is the part a breathing app should sit with. This is not a failure of adherence or of pacing quality — which is exactly what a better-designed app would claim to fix. They did it right, every day, and it did not work.

**Huang et al. 2015.** 123 peri- and postmenopausal women with four or more hot flushes a day, randomised to a device-guided slow-paced breathing trainer or an identical-looking device that played relaxing non-rhythmic music. At 12 weeks paced respiration reduced flushes by 1.8/day (−21%) against music's 3.0/day (−35%), p = .048; for moderate-to-severe flushes, 19% against 44%, p = .02. Paced respiration was **significantly worse than listening to music** ([_Obstet Gynecol_ 125(5):1130–1138](https://pubmed.ncbi.nlm.nih.gov/25932840/)).

**What the same guideline does recommend** for vasomotor symptoms: CBT and clinical hypnosis (Level I), SSRIs/SNRIs, gabapentin, fezolinetant, oxybutynin, weight loss, stellate ganglion blockade. Not recommended alongside paced respiration: yoga, exercise, mindfulness-based interventions, relaxation, acupuncture, supplements.

### The half that survives

Sleep and mood in midlife are a different question from vasomotor symptoms, and there the picture is neutral-to-mildly-positive rather than negative.

In the MsFLASH yoga trial, 12 weeks of yoga did not improve hot flush frequency or bother but **did reduce insomnia symptoms** on the Insomnia Severity Index against usual activity ([Newton et al. 2014, _Menopause_ 21(4):339–346](https://journals.lww.com/menopausejournal/abstract/10.1097/gme.0b013e31829e4baa~efficacy-of-yoga-for-vasomotor-symptoms-a-randomized)). The objective follow-up tempers it: actigraphic sleep parameters in 186 of those women barely moved and did not differ between groups, with one exploratory exception among women whose self-reported sleep was poorest at baseline ([Buchanan et al. 2017, _J Clin Sleep Med_ 13(1):11–18](https://pubmed.ncbi.nlm.nih.gov/27707450/)).

So: a perimenopausal person waking at 3am, or newly anxious, can be offered what önd offers anybody with those problems, on the general evidence, honestly. What may never be offered is relief from the flush itself.

Note where TIM-19's own example phrasing sits. "I'm perimenopausal and waking at 3am" is on the defensible side of that line — it names the sleep, not the flush. That is luck rather than judgement, and TIM-28 should treat it as the boundary rather than the starting point.

### Where perimenopause lands in the catalogue

| Route           | Resolves to                                                       | Why                                                                |
| :-------------- | :---------------------------------------------------------------- | :----------------------------------------------------------------- |
| Night waking    | `extended-exhale` (`SLEEP`)                                       | Long exhale, no hold to strain against, two minutes, doable in bed |
| Winding down    | The `winding-down` occasion                                       | Already exists and already resolves here                           |
| Daytime anxiety | `coherent-breathing` (`CALM`) or the `a-moment-to-reset` occasion | General stress evidence, offered as general                        |
| Never           | Anything framed as a response to a hot flush                      | Level I evidence against                                           |

**Gap found.** The occasion set has `winding-down` for the evening and nothing for 3am. Waking in the night is the single most-described perimenopausal moment and it is a genuinely different occasion from going to bed — different surface (the screen is the enemy at 3am), different duration, different framing, and the person is already lying down. This is a concrete proposal for TIM-19 and TIM-130's successor: an occasion something like "awake at 3am", resolving to `extended-exhale` at `SLEEP` on `DELIVERY_SURFACE_DISCREET` — the surface TIM-130 already shipped, described in `proto/ond/v1/technique_service.proto` as "no animation, no sound", which is exactly what a dark bedroom wants. Nothing new is needed to build this beyond the row itself. It is not a perimenopause feature; it serves everybody who wakes, and that is precisely why it is the right shape.

**And a routing decision hiding as a pricing one.** Every technique this section recommends — `extended-exhale` and `coherent-breathing` — sits behind Plus (`requires_subscription: true` in `crates/migrate/src/seed/catalogue.rs`). ADHD's two routes are both free; perimenopause's are both paid. The seed's own doc comment already flags that "the entries a person meets first should be ones they can breathe" as an open curation question, and this is where it stops being hypothetical: a launch population whose first honest offer is a paywall has been routed to a purchase, not to a breath. Naming it here so it is decided rather than inherited.

### Draft copy for perimenopause

> **Draft, for Tim's review.**
>
> On routing, when the note mentions night waking:
>
> "Awake at three, then. Extended Exhale is in for four and out for six — no holds, nothing to count against, and it works lying down in the dark. Two minutes is the whole thing; you are not being asked to get up."
>
> On routing, when the note mentions hot flushes — the important one, because it is where the temptation is:
>
> "Breathing exercises have been tested for hot flushes properly, and they did not help — so this app is not going to tell you otherwise. What it can do is the sleep and the stress around them, which are their own problem and worth having back. If the flushes themselves are the thing, that is a conversation with a doctor, and a good one to have."
>
> Coach framing, appended to the prompt rather than shown:
>
> "They have described themselves as perimenopausal. Slow breathing has good-quality evidence _against_ it for hot flushes and night sweats — never suggest it for those, and say plainly that it does not work for them if asked. Sleep, stress and anxiety are fair ground, offered on general evidence. Do not discuss hormone therapy or any other treatment."
>
> What we will not say: "ease hot flushes"; "for the menopausal transition"; "balance your hormones"; anything that turns a symptom into a marketing category.

## Athletes

### Arriving as an athlete

"I want to breathe better for racing." "I need to calm down on the start line." "I've heard about Wim Hof."

### Evidence: split down the middle by a distinction the market never makes

**The strong evidence is for something önd cannot do.** Respiratory muscle training — breathing against resistance through a device such as a PowerBreathe, typically 30 breaths at 50–80% of maximal inspiratory pressure, twice daily — improves endurance performance in healthy people. A meta-analysis of eight controlled trials found significant improvement detected by constant-load tests, time trials and intermittent incremental tests ([Illi et al. 2012, _Sports Medicine_ 42(8):707–724](https://link.springer.com/article/10.1007/BF03262290)). This is strength training for the diaphragm. It has nothing in common with a paced breathing app beyond the word "breathing", and any copy that lets an athlete conflate the two is trading on evidence it has not earned.

The same meta-analysis carries a moderator worth stating in the same breath, because it cuts against the population this section is about: less fit individuals benefit more from respiratory muscle training than highly trained athletes do, and gains are larger over longer exercise durations. So the one strong result here is both unavailable to us and weakest in the people most likely to ask about it.

**The evidence for paced breathing as a recovery strategy is weak and getting weaker.** The most direct test to date: 34 participants, four weeks of sprint interval training, daily slow-paced breathing against control. No additional performance improvement and no physiological benefit; nocturnal heart rate rose slightly in the breathing group (+3.1 bpm, 95% CI [0.47, 5.72], p < .05). The authors' conclusion is that slow-paced breathing as applied "cannot be recommended as an effective recovery strategy for sprint interval training" ([Raidl et al. 2026, _Int J Sports Physiol Perform_ 21(2):302–311](https://journals.humankinetics.com/view/journals/ijspp/21/2/article-p302.xml)).

**Between sets, it is neutral.** Eighteen resistance-trained men, five sets of three back squats at 80% 1RM, 4-7-8 breathing during the three-minute rests. Heart rate recovery improved significantly after sets 2 and 3; peak power, average power and bar velocity did not differ at all. It "did not hinder nor improve training performance" ([Buxton et al. 2024, _Journal of Human Kinetics_ 93:93–103](https://pmc.ncbi.nlm.nih.gov/articles/PMC11307190/)).

**The consistent positives are subjective.** Six weeks of twice-daily slow-paced breathing at six breaths a minute in semi-elite adolescent swimmers produced significantly higher biopsychosocial recovery, perceived control and subjective training performance — and no significant effect on stress scales, heart rate or any HRV marker. Note the size before crediting it: thirteen swimmers in total, seven of them in the intervention arm ([Merlin et al. 2024, _J Funct Morphol Kinesiol_ 9(1):23](https://pmc.ncbi.nlm.nih.gov/articles/PMC10885016/)).

**The one review that reads positively is small enough to say so.** A systematic review of HRV biofeedback in athletes concludes that it may be ergogenic for fine and gross motor skills — on six studies covering 187 athletes ([Pagaduan et al. 2020, _Journal of Human Kinetics_ 73:103–114](https://doi.org/10.2478/hukin-2020-0004)). That conclusion belongs in this document precisely because it is the one that would be convenient to leave out, and it does not survive contact with the two most recent direct trials above. And the widely-cited Laborde-group piece on slow-paced breathing for endurance, well-being and sleep in athletes is a perspective article whose authors state plainly that the studies they are calling for do not yet exist ([Borges et al. 2021, _Frontiers in Psychology_ 12:624655](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.624655/full)).

**Verdict.** Moderate for how recovered and in-control an athlete feels, and for pre-competition nerves by extension from the general anxiety evidence. Thin and mixed for performance — one favourable review over six small studies, against two recent trials that found nothing — and absent for objective recovery. That is a narrow claim, and it is still a real one: an athlete who sleeps better and arrives at the line less wound up is not receiving a placebo.

### Safety, which is sharper here than anywhere else

Athletes are the population most likely to have heard of Wim Hof-style breathing, most likely to be near water, and most likely to try combining the two. Pre-immersion hyperventilation lowers arterial CO₂ and delays the urge to breathe, so oxygen falls to critical levels before the drive to surface arrives; **loss of consciousness comes without warning symptoms** ([Shallow Water Blackout, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK554620/); [Royal Life Saving Society UK guidance](https://www.rlss.org.uk/shallow-water-blackout-hyperventilation-and-breath-holding-gs005)). The belief that hyperventilating extends a breath-hold is both wrong and the mechanism of the fatality.

The catalogue already handles this correctly. `bellows-breath` and `wim-hof-rounds` both carry "never in water" in their safety notes, and the onboarding consent carries "Never in water — not in the bath, not in a pool, not beside one." No new copy is needed. What is needed is the discipline not to weaken it: an athlete-facing route must not surface fast-breathing techniques more prominently than it does today, and the Wim Hof summary's honesty about its own evidence base — "thinner on trial evidence than its reputation suggests" — is the single most valuable sentence in the catalogue for this population and must survive any copy pass.

The systematic review of the method is more sympathetic than that summary implies and still supports the same restraint: it finds promising immunomodulatory effects, most clearly when the breathing is combined with cold exposure, while insisting all its results "must be interpreted with caution" on very low study quality, samples of 15–48, and 86% male participants. Enhancing exercise performance is listed among the things future studies should investigate — that is, as an open question rather than a finding ([Almahayni & Hammond 2024, _PLOS ONE_](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0286933)). The catalogue's existing wording is therefore accurate as it stands, and no performance claim may be built on this method.

### Where athletes land in the catalogue

| Route | Resolves to | Why |
| :-- | :-- | :-- |
| Start-line nerves | `box-breathing` (`CALM`), via the shape of the `before-a-presentation` occasion | `CALM`'s own definition names "pre-performance nerves" |
| After a hard session | `coherent-breathing` (`CALM`) — the `after-a-hard-meeting` shape | Where the subjective recovery evidence sits |
| Sleep on the night before | `extended-exhale` (`SLEEP`) | General evidence, offered as general |
| Between sets | `four-seven-eight` or `extended-exhale` | Neutral on power, better heart rate recovery — an honest "won't hurt, might settle you" |
| Not a performance claim | Anything | Nothing in the catalogue improves performance, and the thing that does is a device we do not sell |

Three of those four routes are behind Plus, so the paywall question raised under perimenopause applies here too, and only the start-line route escapes it.

**Gap found, and a smaller one.** `before-a-presentation` and `after-a-hard-meeting` are the right prescriptions for an athlete wearing office clothes. Three of the six seeded occasions are phrased in the vocabulary of desk work; `winding-down` and `a-moment-to-reset` are already audience-neutral, which is why the perimenopause table above can borrow one of them unchanged. "Before the start" and "after training" are the same two prescriptions in different words — same technique, same goal, same surface, same duration. That is an argument that occasion entries are cheap enough to phrase per audience, and that a population's real job may be **choosing which wording of an occasion a person sees** rather than changing what it resolves to. Worth deciding in TIM-28 whether that is one occasion with two names or two occasions with one prescription.

**Since acted on, in part.** `after-a-workout` is seeded — the "after training" half of that pair, and deliberately not the same prescription as `after-a-hard-meeting`. It routes to `extended-exhale` rather than `coherent-breathing`, because straight off hard cardio the drive to breathe is still elevated while CO₂ clears, and a fixed 5.5/min asks somebody to underbreathe through it; a ratio meets them at whatever rate they arrive at. It is reachable but not yet routed to at the moment it happens — noticing a finished workout is TIM-138, and its copy carries the standing rule above about never claiming a performance benefit.

### Draft copy for athletes

> **Draft, for Tim's review.**
>
> On routing:
>
> "Before the start, then. Box breathing for three minutes — four counts a side, and it is the one that works when your hands are shaking. It will not make you faster. It will make the ten minutes before the gun easier to spend."
>
> On the performance question, if asked:
>
> "Straight answer: no. The breathing with an endurance result behind it is resistance training for your diaphragm, through a device — not this, and the effect is smaller the fitter you already are. What slow breathing has behind it is how recovered you feel afterwards and how you sleep. That is worth having, and it is all we are claiming."
>
> Coach framing, appended to the prompt rather than shown:
>
> "They train or compete. Slow breathing has evidence for perceived recovery, pre-competition nerves and sleep; it has none for performance or objective recovery, and the endurance evidence belongs to resistance-device inspiratory training, which this app does not provide. Never claim a performance benefit. Never suggest any fast-breathing or breath-hold technique in or near water."
>
> What we will not say: "breathe your way to a PB"; "train your lungs"; "used by elite athletes"; anything that borrows inspiratory-muscle-training evidence for paced breathing.

## What this contradicts

Five things this research does not confirm, in rough order of how much they should change what gets built.

**1. There is no population for which the evidence supports a different technique.** TIM-60's design-sketch comment set the bar itself: "a condition can only narrow the list if TIM-34's research supports a real difference. Offering 'I have ADHD' as a filter that quietly returns the same exercises as everyone else is worse than not offering it." Having looked, the research supports no such difference for any of the three. What it supports is a difference in **framing, dose, expectation and what we refuse to claim** — which is exactly the D3 decision, and is the reason D3 is right. But the earlier language of populations as a "weighting" over the catalogue should be retired: a weighting implies differential efficacy that does not exist. The population layer touches words, ordering and honesty, and stops there.

**2. Perimenopause fails on its headline symptom, with the best evidence grade there is.** This is the assumption most at risk. If perimenopause was chosen as a launch population partly because hot flushes are a vivid, high-intent search term, that route is closed — not thin, closed, at Level I, with an active-control trial in which listening to music beat the breathing. The population is still worth serving on sleep and stress. It is not worth serving on the thing people will type.

**3. ADHD would have been routed to the wrong shelf.** "ADHD → focus" is the mapping the vocabulary invites, and it would deliver the two most executive-demanding exercises we own to the people least served by them. The right answer for this population is the beginner's ordering that `PROGRESSION` already holds. A population route that lands on an existing generic route is not a failure of the population idea — it is the cheapest possible confirmation that the catalogue was built sensibly.

**4. Occasions beat populations, on all three counts.** Every genuinely useful route found here is an occasion: awake at 3am, before the start, after training, twenty seconds and I cannot sit still. None of them needed a person-label. The population is what makes the occasion _likely_, and the occasion is what carries the prescription. For TIM-19 that suggests the `intent_note` router should aim at an occasion first and fall back to a goal — treating "I'm perimenopausal and waking at 3am" as a night-waking occasion rather than as a perimenopause profile. It also means the two gaps named above (a night-waking occasion; athlete-vocabulary phrasings) are worth more than any population field would be.

**5. The most valuable thing this product can say to all three is what it will not claim.** Each population arrives having been sold something by someone: ADHD by focus apps, perimenopause by hot-flush remedies, athletes by breathwork's borrowed sports-science credibility. In all three cases önd is in a position to be the one that says the disappointing true thing — and the catalogue's existing willingness to mark its own Wim Hof entry as over-hyped shows the voice for it already exists. That is a positioning asset, not a compliance cost, and it is the strongest argument this research produced for the niche framing being right.

## Sources

Guidelines and position statements.

- [The 2023 nonhormone therapy position statement of The North American Menopause Society](https://pubmed.ncbi.nlm.nih.gov/37252752/) — _Menopause_ 30(6):573–590, 2023. Paced respiration: not recommended, Level I. [Recommendation table](https://www.guidelinecentral.com/guideline/9842/).
- [NICE NG87, Attention deficit hyperactivity disorder: diagnosis and management](https://www.nice.org.uk/guidance/ng87/chapter/recommendations).
- [Shallow Water Blackout, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK554620/) and [Royal Life Saving Society UK GS005](https://www.rlss.org.uk/shallow-water-blackout-hyperventilation-and-breath-holding-gs005).

Trials and reviews.

- Fincham GW, Strauss C, Montero-Marin J, Cavanagh K. [Effect of breathwork on stress and mental health: a meta-analysis of randomised-controlled trials](https://www.nature.com/articles/s41598-022-27247-y). _Scientific Reports_ 13:432, 2023.
- Zhang Z, Chang X, Zhang W, Yang S, Zhao G. [The effect of meditation-based mind-body interventions on symptoms and executive function in people with ADHD: a meta-analysis of randomized controlled trials](https://pubmed.ncbi.nlm.nih.gov/36803119/). _Journal of Attention Disorders_, 2023.
- Robe A, Dobrean A, Cristea IA, Păsărelu CR, Predescu E. [Attention-deficit/hyperactivity disorder and task-related heart rate variability: a systematic review and meta-analysis](https://www.sciencedirect.com/science/article/abs/pii/S0149763418308005). _Neuroscience & Biobehavioral Reviews_ 99:11–22, 2019.
- Carpenter JS, Burns DS, Wu J, et al. [Paced respiration for vasomotor and other menopausal symptoms: a randomized, controlled trial](https://pmc.ncbi.nlm.nih.gov/articles/PMC3614127). _J Gen Intern Med_ 28(2):193–200, 2013.
- Huang AJ, Phillips S, Schembri M, Vittinghoff E, Grady D. [Device-guided slow-paced respiration for menopausal hot flushes: a randomized controlled trial](https://pubmed.ncbi.nlm.nih.gov/25932840/). _Obstet Gynecol_ 125(5):1130–1138, 2015.
- Newton KM, Reed SD, Guthrie KA, et al. [Efficacy of yoga for vasomotor symptoms: a randomized controlled trial](https://journals.lww.com/menopausejournal/abstract/10.1097/gme.0b013e31829e4baa~efficacy-of-yoga-for-vasomotor-symptoms-a-randomized). _Menopause_ 21(4):339–346, 2014.
- Buchanan DT, Landis CA, Hohensee C, et al. [Effects of yoga and aerobic exercise on actigraphic sleep parameters in menopausal women with hot flashes](https://pubmed.ncbi.nlm.nih.gov/27707450/). _J Clin Sleep Med_ 13(1):11–18, 2017.
- Illi SK, Held U, Frank I, Spengler CM. [Effect of respiratory muscle training on exercise performance in healthy individuals: a systematic review and meta-analysis](https://link.springer.com/article/10.1007/BF03262290). _Sports Medicine_ 42(8):707–724, 2012.
- Raidl P, Wessner B, Laister S, Csapo R. [No evidence for the efficacy of slow-paced breathing as a recovery strategy after sprint interval training](https://journals.humankinetics.com/view/journals/ijspp/21/2/article-p302.xml). _Int J Sports Physiol Perform_ 21(2):302–311, 2026.
- Buxton JD, Grose HM, DeLuca JD, et al. [The effects of slow breathing during inter-set recovery on power performance in the barbell back squat](https://pmc.ncbi.nlm.nih.gov/articles/PMC11307190/). _Journal of Human Kinetics_ 93:93–103, 2024.
- Merlin Q, Vacher P, Mourot L, Levillain G, Martinent G, Nicolas M. [Psychophysiological effects of slow-paced breathing on adolescent swimmers' subjective performance, recovery states, and control perception](https://pmc.ncbi.nlm.nih.gov/articles/PMC10885016/). _J Funct Morphol Kinesiol_ 9(1):23, 2024.
- Pagaduan JC, Chen YS, Fell JW, Wu SSX. [Can heart rate variability biofeedback improve athletic performance? A systematic review](https://doi.org/10.2478/hukin-2020-0004). _Journal of Human Kinetics_ 73:103–114, 2020. Reads positively; six studies.
- Borges U, Lobinger B, Javelle F, Watson M, Mosley E, Laborde S. [Using slow-paced breathing to foster endurance, well-being, and sleep quality in athletes during the COVID-19 pandemic](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.624655/full). _Frontiers in Psychology_ 12:624655, 2021. Perspective article, not a trial.
- Almahayni O, Hammond L. [Does the Wim Hof Method have a beneficial impact on physiological and psychological outcomes in healthy and non-healthy participants? A systematic review](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0286933). _PLOS ONE_, 2024.
