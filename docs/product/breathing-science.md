# Breathing science specification

The single reference for what önd's catalogue claims and where the science behind each claim comes from: every technique, the pattern as shipped, the mechanism story its copy tells, the trials behind it with design and size, the claims we refuse to make, and the safety facts that bound it. Populations, conditions and proposed additions follow the techniques, because that is the order the doctrine runs in: the technique carries the evidence, the occasion carries the prescription, and no person-label changes either.

This document supersedes two memos now merged into it — _Breathing for ADHD, perimenopause and athletes_ (2026-08-12) and _Catalogue expansion research_ (2026-08-15); their verbatim text, including provisional draft copy, lives in git history. The claim-by-claim ledger for **The basics** screen remains separate in [breathing-foundations.md](breathing-foundations.md), because that page has its own word budgets and seed tests; where the two documents cover the same claim, this one carries the fuller citation and that one the shipped boundary.

Shipped copy lives in [`crates/migrate/src/seed/catalogue.rs`](../../crates/migrate/src/seed/catalogue.rs) — each technique's `mechanism` and `evidence` prose is the user-facing rendering of this specification, and a change to either should keep the two in step.

## 1. The rules of the register

önd is a wellness product. Nothing here supports a treatment claim, an implied diagnosis, or a sentence of the form "helps with X". The register's habits, in force throughout:

- **Say the disappointing true thing.** The catalogue marks its own entries as over-hyped where they are ("thinner than the reputation"). Every population arrives having been sold something by someone; being the app that won't is the positioning asset.
- **"May" for emotional outcomes; "reliably" only for immediate physiological change** supported across studies (the [breathing-foundations.md](breathing-foundations.md) guardrail).
- **Cite the minimal important difference next to the effect.** Where a pooled effect sits under what patients call a meaningful change, say so — the asthma QoL 0.42-vs-MID-0.5 gap and the COPD dyspnoea −0.40-vs-MID-−1.0 gap are the native examples.
- **Report the nulls.** The two best-blinded trials in the field are both nulls against credible breathing shams (§2). Competitor apps cannot say that sentence; önd can.
- **Never any medication language.** No copy, coach reply or occasion may permit, suggest or imply reducing any medication. The Buteyko trials' headline outcome is medication reduction and the hypertension literature invites "instead of pills" framing; this is the highest-severity harm vector in the whole specification.

## 2. The general evidence base

Everything technique-specific competes with the pooled effect of just breathing deliberately at all.

- **Baseline**: breathwork on self-reported stress, g = −0.35 [−0.55, −0.14], 12 RCTs, N=785; anxiety g = −0.32 (k=20); depressive symptoms g = −0.40 (k=18), significant only in non-clinical samples. Mostly unblinded trials against inactive controls ([Fincham et al. 2023, Sci Rep](https://www.nature.com/articles/s41598-022-27247-y)).
- **The two sham-controlled nulls.** Coherent breathing at 5.5 bpm, 10 min/day for 4 weeks, vs a matched 12 bpm placebo, participants blinded, N=400: no difference on stress, anxiety, depression, wellbeing or sleep — both arms improved ([Fincham et al. 2023](https://www.nature.com/articles/s41598-023-49279-8)). Wim Hof-style high-ventilation breathwork with retention vs sham, N=200: null on everything measured ([Fincham et al. 2024](https://www.nature.com/articles/s41598-024-64254-7)). Read together: when the comparator is credible paced breathing of any kind, technique differences evaporate; expectancy plausibly carries a large share of every unblinded effect.
- **Technique choice barely matters.** Rate and ratio manipulated independently within slow breathing: how slowly you breathe predicts calm, exhale-longer-than-inhale adds nothing measurable (N=828, [Czub 2024](https://onlinelibrary.wiley.com/doi/10.1002/smi.3496); 12-week trial 2023). A 2025 review reaches the same conclusion — patterns converge on shared mechanisms, regularity beats session length, expectation is omnipresent ([Siebieszuk et al. 2025](https://www.mdpi.com/2076-3271/13/3/127)).
- **What is reliable**: respiratory sinus arrhythmia and the immediate HRV/baroreflex changes of slow breathing, while you practise ([Shao et al. meta-analysis](https://link.springer.com/article/10.1007/s12671-023-02294-2); [Joseph et al. 2005](https://www.ahajournals.org/doi/10.1161/01.hyp.0000179581.68566.7d)). Lasting emotional or cardiovascular benefit is the less certain half.
- **Dose**: positive multi-week trials cluster at 5–20 minutes a day for 4+ weeks; acute effects appear at ~5 minutes with no measured gain from 20 ([single-bout vagal work](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8656666/)); one-minute doses have preregistered field support for acute state anxiety ([Riedl et al. 2026](https://www.tandfonline.com/doi/full/10.1080/10615806.2026.2659809)). No clear dose-response in the meta-analysis; adherence is the real-world constraint (digital breathing trials find under half of participants meet adherence thresholds).

## 3. The techniques

Each entry: the pattern as shipped, the claim the copy makes, the efficacy record with citations, the refusals, and safety. "Pattern" timings are the seeded defaults; dials move them within authored ranges.

### 3.1 Box Breathing — `box-breathing`

- **Pattern**: nose 4s in · hold 4s · nose 4s out · hold 4s; 19 cycles (~5 min). Goal: Calm.
- **Claim**: the holds let CO₂ rise enough to tip toward the recovering side of the nervous system; four equal counts occupy a rehearsing mind; drilled by military and emergency crews as preparation rather than rescue.
- **Efficacy**: long under-trialled relative to its fame, now firming up. [Balban et al. 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC9873947/) (box arm, n=19): daily mood improved, less than the sighing arm. [Riedl et al. 2026](https://www.tandfonline.com/doi/full/10.1080/10615806.2026.2659809) (preregistered field pilot, N=47, 782 real-life anxiety events): one minute of box matched cyclic sighing on state anxiety, beat it on ease and acceptability (d=.90), and reduced attention commission errors. [McAllister et al. 2026](https://www.psypost.org/brief-breathing-exercises-blunt-the-body-s-physical-reaction-to-acute-stress/) (3-arm RCT, N=66): box and prolonged exhalation both blunted heart-rate, anxiety and salivary alpha-amylase spikes before a speech task. [Collabra 2025 police RCT](https://online.ucpress.edu/collabra/article/11/1/144527/213538/) (N=96): tactical breathing (box under a military name) improved expert-rated critical-incident performance — without lowering self-reported stress.
- **Refusals**: no claim the square beats any other way of breathing slowly ([Röttger et al. 2020](https://pubmed.ncbi.nlm.nih.gov/32757097/): prolonged exhalation did at least as well). Triangle breathing (drop the bottom hold) is the same family, unstudied as a distinct shape.
- **Safety**: none beyond the general consent.

### 3.2 Coherent Breathing — `coherent-breathing`

- **Pattern**: nose 5.5s in · nose 5.5s out (~5.5 bpm); 27 cycles (~5 min). Goal: Calm.
- **Claim**: at ~5.5–6 breaths/min the heart-rate swings of breathing align with the baroreflex rhythm; the settling is cumulative over minutes. Lab-derived (HRV-biofeedback research), the best-trialled pace in the catalogue.
- **Efficacy**: the slow-paced breathing literature is mostly gathered at this pace — small-to-medium reductions in stress and anxiety across meta-analyses ([2024 meta, 31 studies, N=1,133](https://www.researchgate.net/publication/377081073_The_Effect_of_Slow-Paced_Breathing_on_Cardiovascular_and_Emotion_Functions_A_Meta-Analysis_and_Systematic_Review); [Fincham 2023](https://www.nature.com/articles/s41598-022-27247-y)). The immediate baroreflex/HRV change is reliable ([Joseph 2005](https://www.ahajournals.org/doi/10.1161/01.hyp.0000179581.68566.7d)). Against: the [N=400 sham-controlled null](https://www.nature.com/articles/s41598-023-49279-8) at exactly this dose, and a 2026 null for hunting a personal resonance rate over fixed six-a-minute.
- **Hypertension footnote** (the pace maps onto this literature; see §6.6): unblinded trials pool at −3 to −8 mmHg systolic; the device-guided (RESPeRATE) effect disappears when manufacturer-involved trials are excluded ([2022 meta](https://pubmed.ncbi.nlm.nih.gov/35601033/)) and the one blinded active-controlled IPD meta-analysis is [null](https://pubmed.ncbi.nlm.nih.gov/25222103/); 2025 AHA files breathing under "may be reasonable, as an adjunct" (Class 2b). No BP claim, ever.
- **Refusals**: no uniqueness claim for 5.5 bpm; no "coherence" scoring (HeartMath-adjacent framing is contested); no blood-pressure claim.
- **Safety**: none.

### 3.3 4-7-8 Breathing — `four-seven-eight`

- **Pattern**: nose 4s in · hold 7s · mouth 8s out; 8 cycles (Weil's own first-month ceiling — the one entry that does not open on five minutes). Goal: Sleep.
- **Claim**: ~3 breaths/min is the lever; the long exhale makes the pace bearable; the counts are Andrew Weil's packaging of an older pranayama ratio, pointed at the end of the day.
- **Efficacy**: a [2025 scoping review found 15 studies](https://www.researchgate.net/publication/394625657), consistently positive on stress/anxiety in clinical settings; 2024–2026 added unblinded clinical-population nursing RCTs (a [tinnitus trial, N=48, 2026](https://pmc.ncbi.nlm.nih.gov/articles/PMC12895279/) improved insomnia severity; a COPD sleep study moved PSQI). All against information-only controls; no healthy-sleeper RCT; no objective-sleep trial. The pace sits inside the slow range the meta-analyses cover.
- **Refusals**: not a sedative; the specific counts have never beaten any other route to the same unhurried pace; pre-sleep claims lean on the general pre-bed slow-breathing review ([9 studies, N=457 — subjective sleep improves, objective evidence thin](https://www.sciencedirect.com/science/article/abs/pii/S1087079226000560)), not on 4-7-8's own trials.
- **Safety**: shorten all three counts if the hold strains; the ratio, not the numbers, is the exercise.

### 3.4 Extended Exhale — `extended-exhale`

- **Pattern**: nose 4s in · nose 6s out (exhale dial 6–8s); 30 cycles (~5 min). Goal: Sleep (borrowed as Calm by recovery occasions).
- **Claim**: ten seconds a round is six breaths/min, and the pace does the settling; the long out-breath is the shape that is easiest to keep — a ratio meets your breathing wherever it is.
- **Efficacy**: the pace is evidenced, the ratio is not — [Czub 2024 (N=828)](https://onlinelibrary.wiley.com/doi/10.1002/smi.3496) and a 12-week 2023 trial varied rate and ratio independently; slowness predicted calm, the longer exhale added nothing measurable. Prolonged exhalation held its own against box in [McAllister 2026](https://www.psypost.org/brief-breathing-exercises-blunt-the-body-s-physical-reaction-to-acute-stress/) and matched or beat tactical breathing in [Röttger 2020](https://pubmed.ncbi.nlm.nih.gov/32757097/). The UK therapy staple "7-11 breathing" is this technique at other numbers, inside its dials.
- **Refusals**: the ratio is the easy handle, not the active ingredient — no claim that exhale-weighting itself is the mechanism.
- **Safety**: none. (The exhale dial floor sits above the inhale ceiling so no dial setting can invert the ratio.)

### 3.5 Physiological Sigh — `physiological-sigh`

- **Pattern**: nose 1.5s in · nose 1s second sip · nose 5s out; 3 cycles. A spike tool measured in seconds. Goal: Reset.
- **Claim**: the second inhale re-inflates alveoli that fall shut under stress; the following exhale offloads an unusual amount of CO₂; the same reflex the body fires spontaneously every few minutes.
- **Efficacy**: the physiology (alveolar reopening, CO₂ offload) is not in dispute. In-the-moment use now has direct evidence: [Riedl et al. 2026](https://www.tandfonline.com/doi/full/10.1080/10615806.2026.2659809) tested sixty-to-seventy-second doses at real-life anxiety events against control — state anxiety fell, with box breathing exactly as effective. Small, pilot-grade, preregistered.
- **Refusals**: one or two rounds is the claim; a [2026 study of fixed-interval volitional sighing](https://pmc.ncbi.nlm.nih.gov/articles/PMC12811738/) found paced sighs drive a _sympathetic_ cardiovascular response — the "after that it is just breathing" line is load-bearing, not modesty.
- **Safety**: none.

### 3.6 Cyclic Sighing — `cyclic-sighing`

- **Pattern**: nose 2s in · nose 1s sip · nose 7s out; 30 cycles = the trial's five minutes exactly. Goal: Calm. The sigh's daily sibling; the dose is the whole difference.
- **Claim**: strung together, the sighs become a six-breaths/min pace with an exhale long enough to never work at; five minutes a day is the trialled habit.
- **Efficacy**: [Balban et al. 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC9873947/) (N=108 randomised across four arms, 28 days, remote): daily positive affect improved more than mindfulness meditation, resting respiratory rate fell, and benefit grew with cumulative days practised. Caveats that stay in the copy: ~30 per arm, one lab, unblinded, self-report, **no HRV or resting heart-rate changes in any group**, and state anxiety improved equally in all four arms. **No independent replication of the 28-day trial yet.** Independent extensions since: [Hanley et al. 2025](https://pubmed.ncbi.nlm.nih.gov/39904867/) (N=81, orthopaedic waiting room — 4 minutes reduced pain, anxiety null); Riedl 2026 (1-minute acute use works; superiority over box removed).
- **Refusals**: "may lift mood" is the ceiling — never a depression claim (the clinical-population pooled effect is null); no acute-superiority claim over box.
- **Safety**: none.

### 3.7 Bellows Breath — `bellows-breath`

- **Pattern**: nose 1s in · nose 1s out, forceful; 20 cycles (~40s bout). Goal: Energy.
- **Claim**: deliberate exertion-breathing persuades the body exertion has started — heart rate and adrenaline rise; the light head is CO₂ blowing off faster than it is made. Bhastrika, with the tradition's own rules (seated, brief) repeated as the safety note.
- **Efficacy**: small unblinded trials of fast yogic breathing show raised heart rate and shifted alertness/reaction-time measures (a few dozen participants each). The direction is not in doubt — over-breathing is stimulating — the size, and whether it beats standing up, is unstudied. Morning use specifically: the sleep-inertia literature has tested caffeine, light and exercise, never breathing.
- **Refusals**: no claim beyond a short alertness bout. Kapalabhati renders identically in önd's time-symmetric vocabulary and carries a worse safety record (a [pneumothorax case report](https://www.sciencedirect.com/science/article/abs/pii/S001236921532198X); panicogenic risk in vulnerable users) — it is deliberately not a separate entry.
- **Safety** (seeded note): sitting only; stop at lightheadedness; never in water, never driving. Structurally fenced: fast breathing must never be reachable from anxiety- or breathlessness-framed routes (§7).

### 3.8 Wim Hof-style Rounds — `wim-hof-rounds`

- **Pattern**: 30 fast nose breaths · one deep breath · open-ended empty-lung hold (suggested 30s, growing per round) · recovery breath with 15s hold; 3 rounds. Goal: Energy.
- **Claim**: over-breathing pushes back the CO₂-driven urge to breathe, making the empty hold roomy; the adrenaline spike is the bright, electric feel. Hof's packaging of tummo; comfort is the protocol.
- **Efficacy**: the entry's own words — the best trial of it is a null. [Fincham 2024 (N=200, sham-controlled)](https://www.nature.com/articles/s41598-024-64254-7): no benefit on stress, mood or inflammation, more side effects in the active arm. An N=84 trial matched method-plus-cold against slow breathing plus warm showers: level. The [2024 systematic review](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0286933) finds promising immunomodulation mostly when combined with cold, on very low study quality (samples 15–48, 86% male), listing performance enhancement as an open question, not a finding.
- **Refusals**: no performance claim, no immune claim, no cold-tolerance claim; practitioners describe something real, and what has not been shown is that the hyperventilating and holding produce it.
- **Safety** (seeded note): seated or lying, never in water or the bath, never driving or standing; no hold measured or pushed. The mechanism of shallow-water blackout — hyperventilation delays the urge to breathe until oxygen is critically low, and **loss of consciousness arrives without warning** ([StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK554620/); [RLSS UK](https://www.rlss.org.uk/shallow-water-blackout-hyperventilation-and-breath-holding-gs005)) — is the sharpest safety fact in the catalogue, sharpest of all for athletes (§5.3).

### 3.9 Long Box Breathing — `long-box-breathing`

- **Pattern**: 6-6-6-6 (dials to 10s a side); 13 cycles (~5 min). Goal: Focus.
- **Claim**: the concentration is the exercise — six-count sides must be steered, and the holds are where a wandering mind gets caught. Underneath, still slow even breathing.
- **Efficacy**: no trials of its own; the long sides are a stated craft judgement over the same slow-breathing base. The focus framing is a description of how it feels to do, not a finding about attention — the copy says so.
- **Refusals / Safety**: as box breathing. Highest executive load in the catalogue alongside alternate-nostril — never surfaced first to anyone describing difficulty settling (§5.1).

### 3.10 Alternate-Nostril Breathing — `alternate-nostril`

- **Pattern**: left in 4s · right out 6s · right in 4s · left out 6s; 15 cycles (~5 min). Goal: Focus.
- **Claim**: the hand choreography cannot run on autopilot, so attention settles on the breath; nadi shodhana, centuries old; underneath, slow nasal breathing.
- **Efficacy**: a 2024 meta-analysis pooled blood-pressure trials to meaningful reductions with enormous heterogeneity (>75% of variation between trials — the pooled number does not describe one effect); anxiety work is pilot-sized. **Acute caution, newly firm**: a [2024 systematic review of brief state-anxiety interventions](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2024.1412928/full) found alternate-nostril did _worse_ than control acutely, and the one simulated-public-speaking RCT was [null](https://pmc.ncbi.nlm.nih.gov/articles/PMC5660749/) (N=30).
- **Refusals**: nothing separates the nostrils from slow nasal breathing with something to concentrate on; **never routed to any in-the-moment or performance occasion** — a sitting, only.
- **Safety**: none.

### 3.11 Breathing Together — `breathing-together`

- **Pattern**: nose 3s in · nose 5s out; 8 cycles (~1 min), designed to end while still going well. Goal: Calm; Playful register.
- **Claim**: a slow breath with an easy long out-breath works without being understood; children read a calm adult faster than they follow one — the adult breathes visibly, the counting is theirs.
- **Efficacy**: an application of the adult slow-breathing evidence, stated as such — nothing tested with children at this pace. The child yoga/mindfulness literature (e.g. [Tanksale 2021, N=61–67](https://journals.sagepub.com/doi/10.1177/1362361320974841)) supports short, concrete, enjoyable practice without isolating breathing. Five-finger/star breathing's tactile trace is a related child staple with no direct trials; this entry owns the moment.
- **Safety** (seeded note): no holds and none added — breath-holding and fast breathing are not for children; stop at dizziness or lost enjoyment.

## 4. Proposed additions (undecided; seed-ready)

From the August 2026 expansion research. Feasibility notes refer to the seed machinery: dial floors and the blackout rule are satisfied throughout; each new slug needs a `DOSES` band; the safety-note set is pinned by test to exactly three techniques and adding a fourth is a deliberate test edit.

### 4.1 Tier 1

**Pursed-lip breathing** (new technique, goal Calm) — nose 2s in (2–4) · pursed-lip mouth 4s out (4–8), 30 cycles, bespoke 150–210s dose band, dial reaching a ten-breath rescue. Genuinely distinct: expiratory resistance (~5 cmH₂O splinting floppy airways against collapse) at ~10 bpm — a mechanism and pace nothing in the catalogue has. Evidence: the most-taught technique in respiratory care; [2024 ERS review, 73 RCTs, N=5,479](https://publications.ersnet.org/content/errev/33/174/240012) — small dyspnoea reduction below the meaningful-change threshold; [Cochrane](https://www.cochrane.org/CD008250/AIRWAYS_breathing-exercises-for-chronic-obstructive-pulmonary-disease) ~50 m walking-distance gain and nothing added on top of exercise training; responders and non-responders both real; unstudied for calm in healthy lungs. Wants the fourth safety note (red-flag triage: practise calm before you need it winded; new, severe or non-settling breathlessness is a doctor). Occasion: `when-youre-winded` (FullScreen, 120s). No voice render needed — the lips live in copy, like the nostrils.

**`awake-at-3am`** (occasion) — `extended-exhale`, Sleep, Discreet, 300s. Carried from the populations memo; different surface (the screen is the enemy), person already lying down, serves everyone who wakes. One row.

**Copy pass on five existing entries** — the §3 updates for box, physiological sigh, cyclic sighing, 4-7-8 and alternate-nostril, keeping the register's claim of currency true.

### 4.2 Tier 2

**Humming breath (Bhramari)** (new technique, goal Calm) — nose 4s in (3–6) · nose 8s hum out (6–15), 25 cycles (fits the standard 270–330s sitting band). The one candidate with a mechanism nothing else touches: humming's oscillating airflow ventilates the paranasal sinuses and raises nasal nitric oxide **15-fold** — replicated, uncontested ([Weitzberg & Lundberg 2002](https://pubmed.ncbi.nlm.nih.gov/12119224/)). Clinical outcomes rest on [~6 small RCTs among 46 studies](https://ijpp.com/exploring-the-health-benefits-of-bhramari-pranayama-humming-bee-breathing-a-comprehensive-literature-review/); the famous sinusitis story is a [single case report](https://pubmed.ncbi.nlm.nih.gov/16406689/) and the copy says so in those words. The hum physically forces the exhale nasal; the user supplies the sound, so no voice render.

**Occasions**: `riding-out-a-craving` (`extended-exhale`, Reset, Discreet, 180s — [small RCTs](https://pubmed.ncbi.nlm.nih.gov/22993051/) show minutes of relief for cigarette craving, no cessation effect, unstudied-to-negative for food); `when-you-cant-get-a-satisfying-breath` (`extended-exhale`, Calm, FullScreen, 300s — the dysfunctional-breathing constituency, §6.7); `in-a-tight-spot` (`extended-exhale`, Calm, Discreet, 300s — the [MRI completion RCT, 91% vs 26%](https://pmc.ncbi.nlm.nih.gov/articles/PMC10702764/), single-centre and unblinded; flying explicitly untested); `feeling-queasy` (`coherent-breathing`, Calm, Discreet, 180s — post-op wards, rotating chairs, a 2024 chemo RCT; "buys minutes of tolerance, weaker than medication").

**Foundations additions**: _"Is a deep breath always the answer?"_ (no — gentle and slow beats big and deep when panic is rising; over-breathing is the commoner failure; §6.4); _"When breathing itself is the problem"_ (dysfunctional breathing: common, real, treatable; slow nasal practice is the standard retraining); a permission line for breath-focus aversion (follow the figure, not the feeling; stopping early is fine); a device-honesty sentence (the strongest blood-pressure results belong to calibrated resistance trainers and capnometers — different tools, not this app); a mouth-taping non-endorsement ([2025 systematic review: 10 low-quality studies, limited benefit, real risk with nasal obstruction](https://pmc.ncbi.nlm.nih.gov/articles/PMC12094774/)).

**The nasal habit, elevated.** The durable meta-claim above every technique: habitual nasal breathing — day-to-day, at rest, during easy exertion — with any session doubling as practice for it. The physiology is real and uncontested (filtration, warming, humidification, an airway resistance that naturally slows the breath, sinus nitric oxide joining the airstream); the honest boundary stays (magnitude of benefit in healthy people uncertain; no oxygen-transfer overclaim). Rewrite the `nose-or-mouth` foundations entry to lead with the habit — "the session is practice for the day" — and let Bhramari's nitric-oxide story cross-reference it. The mouth-taping refusal lives here too: the goal is nasal days, not taped nights.

### 4.3 Tier 3 — decisions rather than recommendations

- **`light-and-slow`** (panic candidate; technique) — nose 2.5s in (2–3.5) · nose 4.5s out (3.5–6.5), ~26 cycles, ~9 bpm with deliberately _small_ breaths. The trialled panic-adjacent shape (§6.4), outside every existing dial floor. Against: a second nose-ratio figure in the catalogue, and an evidence paragraph that must admit the mechanism is contested. If it ships: occasion `when-panic-is-rising`, FullScreen, 180s. If not, the "deep breath" foundations correction carries most of the value.
- **`ten-quiet-minutes`** (occasion) — `coherent-breathing`, 600s: the hypertension-dose habit (100–200 min/week is where the unblinded dose-response points). Overlaps `five-minutes-today` philosophically; decide whether a second daily door enriches or dilutes.
- **`overloaded-and-need-quiet`** (occasion) — `box-breathing` or `extended-exhale`, Discreet, 180s: the sensory-overload moment, serving the autism-adjacent need the way 3am serves perimenopause; zero moment-specific evidence, general acute base only, and the copy would say so.
- **Sitali/sitkari** stays shelved unless a cooling occasion is wanted (one N=100 hypertension RCT; the cooling claim itself untested; the only mouth-inhale technique, so expressible).

### 4.4 Considered and excluded

| Candidate | Why not |
| :-- | :-- |
| Buteyko | Active ingredient is a volume/depth axis the app cannot express; diagnostic is a scored breath-hold önd refuses by principle; headline trial outcome is medication reduction (~7 asthma RCTs: symptoms and medication use improve, lung function never does — [Bowler 1998](https://pubmed.ncbi.nlm.nih.gov/9887897/) et seq.). Foundations paragraph at most. |
| Ujjayi | The one controlled comparison ([Mason 2013](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3655580/)): slow breathing _without_ the glottal resistance beat slow breathing with it, in yoga-naive subjects. Renders pixel-identical to coherent. |
| Breath counting | Real evidence as a validated mindfulness _measure_ ([Levinson 2014](https://pubmed.ncbi.nlm.nih.gov/25386148/)); the technique is definitionally unpaced — a pacing app's faithful rendering is a blank screen. |
| Sudarshan Kriya | Moderate depression evidence, a veterans noninferiority PTSD trial — and a chant-paced, instructor-delivered ritual, structurally inexpressible, with provenance claims önd shouldn't inherit. |
| Papworth | Five physiotherapist sessions whose breathing ingredients are the catalogue's slow entries already. A programme, not a pattern ([Holloway & West 2007, N=85](https://pmc.ncbi.nlm.nih.gov/articles/PMC2094294/)). |
| Diaphragmatic breathing (as an entry) | A somatic cue, not a pattern — at trial paces it _is_ coherent breathing; belly-cue line in copy instead, with the severe-COPD harm caveat (§6.5). |
| Tactical breathing, 7-11, sama vritti, triangle, 4-4-8, five-finger | Existing entries under other names, or unstudied hybrids — folded into copy where useful. |
| Kapalabhati | Renders identical to bellows in a time-symmetric vocabulary; worse safety profile. |

## 5. Populations

The law, tested against eight literatures and standing: **no population justifies a different technique, and occasions beat populations.** What a population changes is framing, dose, expectation and what we refuse to claim. Every genuinely useful route found in three research passes is a moment; the population makes the moment likely, the moment carries the prescription.

### 5.1 ADHD

- **Evidence**: no RCT of a breathing technique as a standalone ADHD intervention worth building copy on. Meditation-based mind-body packages pool to small effects (inattention g = −0.26, executive function g = −0.35 — [Zhang 2023](https://pubmed.ncbi.nlm.nih.gov/36803119/)) with no part attributable to breathing, no blinding, mostly inactive controls. [NICE NG87](https://www.nice.org.uk/guidance/ng87/chapter/recommendations) does not recommend standalone mindfulness for core symptoms. Reduced task-time vagal HRV is a plausible mechanism and nothing more ([Robe 2019, 13 studies](https://www.sciencedirect.com/science/article/abs/pii/S0149763418308005)).
- **The product finding**: "ADHD → Focus" is the wrong mapping — the two Focus techniques are the two highest-executive-load exercises in the catalogue. The right response is the beginner's ordering the progression already encodes: box breathing (one number), then the physiological sigh (seconds). A population route that lands on an existing generic route is the cheapest confirmation the catalogue was built sensibly.
- **We will not say**: "breathing helps ADHD"; "improves focus and attention"; anything naming the diagnosis back at the person. Coach rule: prefer short sessions, single counts, one instruction at a time; never suggest breathing as treatment.

### 5.2 Perimenopause

- **Evidence, and it points the other way**: paced breathing for hot flushes is **not recommended at Level I evidence** — the Menopause Society's highest grade ([2023 position statement](https://pubmed.ncbi.nlm.nih.gov/37252752/)). [Carpenter 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3614127) (N=218, active-controlled): null despite correct daily practice. [Huang 2015](https://pubmed.ncbi.nlm.nih.gov/25932840/) (N=123): paced respiration was significantly _worse than listening to music_. The route is closed — not thin, closed.
- **What survives**: sleep and mood in midlife, offered on the general evidence as general ([MsFLASH yoga: insomnia symptoms improved](https://journals.lww.com/menopausejournal/abstract/10.1097/gme.0b013e31829e4baa~efficacy-of-yoga-for-vasomotor-symptoms-a-randomized), actigraphy mostly unmoved). Night waking → `extended-exhale`; winding down → the existing occasion; the 3am occasion (§4.1) is this population's real gap, and rightly serves everybody.
- **We will not say**: "ease hot flushes"; "for the menopausal transition"; "balance your hormones". Coach rule: good-quality evidence _against_ slow breathing for vasomotor symptoms — say plainly it does not work for them if asked; sleep/stress/anxiety are fair ground; no hormone-therapy discussion.

### 5.3 Athletes

- **Evidence, split by a distinction the market never makes**: the strong endurance result belongs to inspiratory muscle _training_ against a resistance device ([Illi 2012 meta](https://link.springer.com/article/10.1007/BF03262290)) — strength training for the diaphragm, unavailable to a pacing app, and weakest in the fittest. Paced breathing as recovery: the most direct trial found no performance or physiological benefit and slightly _raised_ nocturnal heart rate ([Raidl 2026, N=34](https://journals.humankinetics.com/view/journals/ijspp/21/2/article-p302.xml)); between sets it is neutral on power with better heart-rate recovery ([Buxton 2024, N=18](https://pmc.ncbi.nlm.nih.gov/articles/PMC11307190/)); the consistent positives are subjective recovery and control ([Merlin 2024, N=13](https://pmc.ncbi.nlm.nih.gov/articles/PMC10885016/)). Start-line nerves now have direct task-specific support via box breathing (§3.1, McAllister 2026).
- **Safety, sharper here than anywhere**: athletes are likeliest to have heard of Wim Hof, likeliest to be near water, likeliest to combine them. The shallow-water-blackout mechanism (§3.8) is the reason the "never in water" lines exist and must survive every copy pass.
- **We will not say**: "breathe your way to a PB"; "train your lungs"; "used by elite athletes"; anything borrowing inspiratory-muscle-training evidence for paced breathing. Coach rule: perceived recovery, nerves and sleep are claimable; performance and objective recovery are not; never any fast-breathing or breath-hold technique in or near water.

### 5.4 Autism and neurodivergence beyond ADHD

- **Evidence**: no adequately powered RCT of a standalone breathing exercise for anxiety in autistic people. The closest analogue — HRV biofeedback, operationally slow breathing at ~6 bpm — is pilot-stage (N≤24/arm; one [sham-controlled trial](https://pubmed.ncbi.nlm.nih.gov/38491260/) moved physiology, not functioning). Cyclic sighing, box, 4-7-8: unstudied in autism, stated plainly.
- **The strongest findings are design findings**: intolerance of uncertainty correlates with anxiety in autism at r = 0.62 and is literally a desire for predictability ([Jenkinson 2020 meta](https://journals.sagepub.com/doi/full/10.1177/1362361320932437)) — fixed patterns, explicit counts and no surprise transitions target the measured mechanism; a neutral, predictable app reads as "safe" to autistic adults ([2025 qualitative](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12408516/)); haptic pacing beats voice in general-population work, with the autism-specific caveat of vibrotactile _hyper_-sensitivity — haptic strength must stay adjustable and removable (it is; keep it so on the watch path).
- **Breath-focus aversion is real for a hyperaware subgroup**: involuntary body-signal hyperawareness is itself anxiety-inducing for some ([Adams 2025](https://journals.sagepub.com/doi/full/10.1177/13623613251314595)); ~50% alexithymia co-occurrence ([Kinnaird 2019](https://www.sciencedirect.com/science/article/pii/S0924933818301779)); the largest anxiety RCT in autistic adults ([ADIE, N=121](https://www.thelancet.com/journals/eclinm/article/PIIS2589-5370(21)00322-9/fulltext), d=0.30 — no breathing component) logged one adverse event of body-focus-triggered anxiety. Mitigation is what önd builds anyway: an external pacer to follow rather than a feeling to find, plus the foundations permission line (§4.2).
- **Tourette's**: breathing appears only inside CBIT's relaxation component; standalone relaxation was null at 3 months ([Bergin 1998](https://pubmed.ncbi.nlm.nih.gov/9535299/)). Never framed as tic treatment. **Dyspraxia, dyslexia**: nothing found; unstudied, said plainly.
- **We will not say**: any autism-specific efficacy claim; any population label on a route. The state-framed occasion (`overloaded-and-need-quiet`, §4.3) is the shape that serves without labelling.

## 6. Conditions

Research covers conditions freely; the app frames only moments. Each subsection ends with its routing consequence.

### 6.1 Panic

Panic-prone people tend to _over_-breathe (hypocapnia produces the dizziness, tingling and air hunger); "take a deep breath" is bad advice mid-attack ([Meuret](https://www.nbcnews.com/health/health-news/stave-panic-attacks-dont-take-deep-breath-flna1c9468736)). The trialled therapy (CART) slows to ~9/min with deliberately _small_ breaths against a capnometer (40% panic-free post-treatment; [multisite 83% response](https://link.springer.com/article/10.1007/s10484-017-9354-4)) — but [Kim, Wollburg & Roth 2012](https://www.semanticscholar.org/paper/725ca316722a51b2e3b2fe508637c9c0e9a90a2b) found raising and lowering CO₂ worked equally, so pacing and self-efficacy may carry the effect; and dismantling studies find breathing retraining adds little to CBT and can teach sensation-avoidance ([Schmidt 2000](https://pubmed.ncbi.nlm.nih.gov/10883558/)). **Routing**: gentle, slow, small, nasal; no big inhales, no long holds, never bellows or Wim Hof; the `light-and-slow` candidate (§4.3) or extended exhale; copy normalises sensations rather than promising to abolish them.

### 6.2 PTSD

The one direct RCT of breathing retraining for PTSD hyperarousal is null (N=80 veterans; baseline CO₂ was not low — the panic model does not transfer; [Jamison 2019](https://www.ptsd.va.gov/professional/articles/article-pdf/id1548512.pdf)). SKY's trials ([Seppälä 2014, N=21](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4309518/); [Bayley 2022 noninferiority, N=85](https://pmc.ncbi.nlm.nih.gov/articles/PMC9422818/)) are small, unblinded, multi-component and inexpressible. Breath focus can be triggering in trauma. **Routing**: nothing, ever — no occasion, no framing. The comfort accommodation (§4.2 permission line, easy exits, no-hold defaults on calming routes) is the entire product response.

### 6.3 Depression and general anxiety

Depression: pooled effects hold only in non-clinical samples; every clinical trial is a pilot. Anxiety: the g = −0.32 base plus the §2 sham nulls; slow pace, structure and multi-week practice associate with effectiveness, exact pattern does not ([Bentley 2023, 58 studies](https://pubmed.ncbi.nlm.nih.gov/38137060/)). **Routing**: existing calm entries as general; "may lift mood" (cyclic sighing's trialled outcome) is the ceiling; GAD as a disorder is out of claim range.

### 6.4 Asthma

Breathing retraining moves symptoms and QoL, never lung function ([Cochrane, 22 RCTs, N=2,880](https://www.cochrane.org/evidence/CD001277_breathing-exercises-asthma) — QoL 0.42 vs MID 0.5, moderate certainty at ≤3 months, null at 6). [BREATHE (N=655)](https://pubmed.ncbi.nlm.nih.gov/29248433/): a self-guided programme matched face-to-face physiotherapy — the strongest precedent that an unsupervised medium can carry retraining. GINA files breathing exercises as adjunct-tier. **Routing**: nothing asthma-named; foundations paragraph; the no-medication rule (§1) exists chiefly for this literature and Buteyko's.

### 6.5 Breathlessness — COPD, deconditioning, and the belly-breathing caution

Pursed-lip breathing's case is §4.1. The counterweight: _diaphragmatic_ breathing — the internet's default advice — has documented harm in severe COPD: chest-wall motion turns asynchronous and mechanical efficiency falls ([Gosselink 1995](https://pubmed.ncbi.nlm.nih.gov/7697243/)); gas exchange improves while dyspnoea _worsens_ ([Vitacca 1998](https://publications.ersnet.org/content/erj/11/2/408)). **Routing**: no belly-expansion cue reachable from any breathlessness frame; every breathlessness-shaped route opens with red-flag triage (new, severe or non-settling breathlessness is a clinician or an emergency number).

### 6.6 Hypertension

Unblinded slow-breathing trials pool at −3 to −8 mmHg systolic with I²≈90% and universal bias risk ([Garg 2023, 15 RCTs](https://pmc.ncbi.nlm.nih.gov/articles/PMC10765252/)); the device-guided effect vanishes without manufacturer involvement; the blinded IPD meta-analysis is null; AHA 2025: "may be reasonable, as an adjunct" (Class 2b). IMST's −9 mmHg ([Craighead 2021](https://www.ahajournals.org/doi/10.1161/JAHA.121.020980)) is the largest effect anywhere in this spec and belongs entirely to a calibrated resistance device. **Routing**: no BP claim; the dose maps onto coherent breathing as it exists; the honest device null is a foundations credibility asset.

### 6.7 Dysfunctional breathing — the hidden constituency

Roughly [one in ten adults](https://pubmed.ncbi.nlm.nih.gov/11337441/), a third of treated asthma patients, and 30–40% of unexplained-dyspnoea and long-covid cohorts breathe in a symptom-generating pattern with no lung disease — air hunger, sighing, chest tightness, tingling. These people are disproportionately likely to be inside a breathing app. önd's slow nasal entries already _are_ the standard physiotherapy retraining ([68 studies, 19 randomised — consistently positive, consistently low quality](https://pubmed.ncbi.nlm.nih.gov/40345332/)). **Routing**: the `satisfying-breath` occasion (§4.2) serves them without the syndrome's name; fast breathing is the exact wrong prescription for them — the fence in §7 exists chiefly for this group; the Nijmegen questionnaire is never shipped as a self-test.

### 6.8 Long covid

The best-evidenced programme is singing-based (ENO Breathe): [RCT N=150](https://www.thelancet.com/journals/lanres/article/PIIS2213-2600(22)00125-4/fulltext) — mental-health QoL up (+2.42, barely significant), most breathlessness measures unmoved; [2026 real-world cohort, N=1,438](https://www.thelancet.com/journals/landig/article/PIIS2589-7500(26)00011-7/fulltext) — 61% clinically meaningful breathlessness improvement, uncontrolled. The replicable ingredient is the slow extended exhale; the choir and specialist may carry much of the effect. Post-exertional symptom exacerbation is the governing safety fact (7 of 16 trial withdrawals were fatigue). **Routing**: short sessions only, never escalating, "stop if it's tiring you; more is not better here."

## 7. Standing rules

1. **The hyperventilation fence.** No occasion framed around breathlessness, air hunger, chest tightness, panic or anxiety may route to a technique with a fast-breathing stage (dial-floor cycle under `FAST_BREATHING_CYCLE_MS`). Holds vacuously today (bellows and Wim Hof carry goal Energy and no occasion routes to them); worth a seed test in the shape of the existing pinned-set tests so it holds structurally.
2. **No medication language, ever** — copy, coach and occasions alike (§1).
3. **Red-flag triage on every breathlessness-shaped route** (§6.5), carried by the pursed-lip safety note if Tier 1 ships.
4. **No belly-expansion cue reachable from a breathlessness frame** (§6.5).
5. **Alternate-nostril stays off acute and performance routes** (§3.10); **the sigh doesn't overdose** (§3.5).
6. **Wim Hof's honesty is load-bearing** — "thinner on trial evidence than its reputation suggests" is the single most valuable sentence in the catalogue for the athlete population and survives every copy pass, as do all "never in water" lines.
7. **Breath-focus aversion gets an exit** — permission to follow the external pacer, shorten, or stop, without it being failure (§5.4).
8. **Populations touch words, ordering and refusals — never efficacy.** A "weighting" over the catalogue implies differential efficacy that does not exist.

## 8. Verification notes

Three citations in this spec were confirmed only from abstracts or secondary summaries and must be re-verified before being quoted in shipped copy: the exact GINA 2025 breathing-exercise wording; the 2025 AHA/ACC recommendation class text; the pooled estimates of the 2026 _Explore_ Buteyko meta-analysis. The 2026 Clin Cardiol hypertension meta-analysis shares a suspicious N=1,097 with Garg 2023 and is excluded from the numbers above pending that check.
