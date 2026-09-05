# Complete source-copy audit — 5 September 2026

The copy needs another release pass. The main problems are conflicting safety instructions, privacy promises that disagree with the implementation, and paid-feature or recovery wording that overstates what happens. Much of the everyday instruction copy is already clear; a wholesale change of voice would add work without addressing these problems.

This report records **27 findings: 12 release priorities, 12 clarity and consistency improvements, and three editorial improvements** at the audit baseline. The [remediation status](2026-09-05-copy-remediation-status.md) records subsequent implementation and remaining verification. Suggested text below is the original proposal, not clinical approval.

## Scope and evidence

Reviewed the current local source at `0b6a8ad2a`, including the previous release polish, selected icon A, sequential phone instruction transition and removal of the duplicate Watch clock. This supersedes the earlier _targeted_ copy review, not the wider release audit.

The [coverage inventory](2026-09-05-copy-coverage.md) records the file boundary: 377 native Swift files screened, of which 271 contain string-literal candidates, plus native permission descriptions, server-authored text, the bundled catalogue, three website pages and local listing material. Candidate lines include keys, logging and debug text; these numbers are **not counts of user-facing strings**. The editorial pass covered headings, buttons, body text, safety instructions, empty/error states, subscription and consent copy, notification content, accessibility strings, Live Activities, Watch and complication text, and interpolated wording.

All 13 exercises, 13 Basics topics, 17 Moments and five introductory steps were reviewed in the authored seed. The bundled JSON has the same record counts. Existing research ledgers were consulted to distinguish unsupported expansion from an intentionally limited claim. This was not a fresh systematic review of every cited study.

Evidence below is source evidence. A code path establishes that wording can be presented; it does not establish that every state has been rendered on a device. Model-generated replies and user-authored exercise names cannot be exhaustively enumerated. Their prompts, fixed fallbacks and presentation contracts were reviewed. Live provider output, deployed website/catalogue, App Store Connect metadata, OS-owned dialogues and device pronunciation remain separate verification work.

## Release priorities

Priority means recommended order before release, not a finding of legal noncompliance or a clinical diagnosis.

### COPY-01 — Accessibility instructs a maximum breath hold

**Evidence:** [TechniqueFigureDrawing.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueFigureDrawing.swift), line 181, constructs “for as long as you can”, followed by a typical duration range. [BreathRhythmChart.swift](../../ios/Ond/Features/Techniques/BreathRhythmChart.swift), line 38, exposes the figure's spoken text as its accessibility label. The Wim Hof-style catalogue guidance instead says to end each hold while comfortable and that longer is not better.

**Change:** replace the maximum-effort instruction with “Hold only while comfortable. End the hold when you need to breathe.” Remove the typical duration from the instruction, or clearly separate it from any target. Keep the existing option to end a hold.

**Close when:** spoken chart, written steps and live hold guidance express the same comfortable-stop rule. Review with VoiceOver and obtain clinical agreement on the final wording.

### COPY-02 — Tingling receives conflicting instructions

**Evidence:** [SafetyConsent.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/SafetyConsent.swift) calls tingling “ordinary”; the Wim Hof-style safety note does the same. The Basics topic on a comfortable breath instead advises making the breath smaller and slowing down if tingling or dizziness appears. The opening “the few ways they don't” also makes the safety list sound exhaustive.

**Change:** use one approved symptom response across consent, technique warnings, Basics and coach instructions. A conservative draft is “Stop the exercise and return to your normal breathing if you feel dizzy, lightheaded or tingly.” Replace the introductory reassurance with “Keep the breath comfortable. Read these precautions before you begin.” A clinician should settle the precise stop/ease distinction and escalation wording.

**Why:** tingling and lightheadedness can accompany overbreathing, whose cause is not necessarily anxiety. [MedlinePlus: Hyperventilation](https://medlineplus.gov/ency/article/003071.htm).

**Close when:** the same symptom produces the same instruction on phone and Watch, including first-run consent and fast-breathing routes.

### COPY-03 — A Watch route suggests use in a scanner

**Evidence:** [catalogue.rs](../../crates/migrate/src/seed/catalogue.rs), `in-a-tight-spot`, recommends a discreet rhythm “in a scanner, lift or crowded journey”. Its delivery surface is the Watch route; the adjoining source comment explicitly imagines somebody inside a scanner.

**Change:** “Use a discreet slow rhythm in a lift or on a crowded journey.” Remove the scanner example. Any future medical-procedure use case needs instructions agreed with the provider rather than a general wearable recommendation.

**Why:** “scanner” can include MRI, where metal objects and external electronic devices require screening. The copy should not imply that a Watch is suitable there. [FDA: MRI benefits and risks](https://www.fda.gov/radiation-emitting-products/mri-magnetic-resonance-imaging/benefits-and-risks).

**Close when:** the example is absent from seed, bundle, coach context and public copy.

### COPY-04 — Breathlessness reassurance and precautions depend on the entry route

**Evidence:** [catalogue.rs](../../crates/migrate/src/seed/catalogue.rs), `when-you-cant-get-a-satisfying-breath`, combines reassurance about most cases with a safety note. `when-breathing-is-the-problem` introduces a treatable pattern in people with healthy lungs. Pursed-Lip Breathing offers recovery when already short of breath but has an empty technique safety note; the “When you're winded” Moment carries the caution instead. Reading or launching the exercise directly does not supply that Moment's context.

**Change:** remove population-level reassurance that a reader might apply to an unexplained symptom. Add a short, shared, clinically approved boundary wherever breathlessness is presented as a reason to practise. Draft: “Do not use this exercise to assess unexplained breathlessness. Seek medical advice for new or worsening symptoms.” Give clear emergency action for severe symptoms in the approved expanded guidance; do not bury it behind an optional Basics link.

**Why:** breathlessness has multiple causes, and urgent action depends on accompanying symptoms. [NHS: Shortness of breath](https://www.nhs.uk/symptoms/shortness-of-breath/).

**Close when:** exercise, Moment, Basics and coach routes have been checked independently. Clinical review should preserve useful reassurance without implying that the app has assessed the cause.

### COPY-05 — Check-ins imply validated improvement and discourage an early stop

**Evidence:** [BoltTestView.swift](../../ios/Ond/Features/CheckIns/BoltTestView.swift) says “This measures how settled your breathing is”, “Do not stop before it” and “Your best yet.” [RestingRateTestView.swift](../../ios/Ond/Features/CheckIns/RestingRateTestView.swift) says “Your slowest yet” and describes values outside the accepted range as beyond where resting breathing goes. [CheckInsView.swift](../../ios/Ond/Features/CheckIns/CheckInsView.swift) celebrates longest/slowest values. The [foundations ledger](../product/breathing-foundations.md) explicitly rejects interpreting popular scores as established health outcomes.

**Change:** “This records the time until your first urge to breathe. It is not a health score. You can stop at any time.” Use “Recorded” and “Previous reading” in place of best/slowest celebrations. For out-of-range input: “This is outside the range önd records. You can discard this reading and try again when comfortable.” Do not describe an app validation limit as a physiological impossibility.

**Close when:** check-ins, history, comparison explanations and coach interpretations agree. Clinical/product review must decide whether physiological leaderboards should retain their current targets; changing the words alone will not settle that decision.

### COPY-06 — The coach's authored brief contradicts the evidence stance

**Evidence:** [coach prefix](../../crates/api/src/features/assistant/prompt/copy/prefix.md) treats resting rate as evidence of whether practice is helping and describes BOLT bands using “strong” and “excellent”. It also instructs the coach never to contradict Foundations, but [prefix.rs](../../crates/api/src/features/assistant/prompt/prefix.rs) supplies the Foundations questions without their answers. Instructions to avoid alarm must not soften appropriate escalation.

**Change:** explicitly state that these readings do not establish health improvement, should not become performance targets, and cannot identify the cause of symptoms. Give the model the approved interpretation and stop rules, not just the question titles. Prefer “Your latest reading differs from your earlier readings” to a verdict about better breathing.

**Close when:** the static prompt matches the ledger, then sample live replies for high/low scores, symptom reports, requests for longer holds and comparisons with other people. Prompt edits alone cannot certify all future responses.

### COPY-07 — Physiological-sigh dose differs between description, prompt and practice

**Evidence:** [catalogue.rs](../../crates/migrate/src/seed/catalogue.rs), `physiological-sigh`, describes one or two double breaths; its default stage offers three cycles. `a-moment-to-reset` lasts 60 seconds. The [coach prefix](../../crates/api/src/features/assistant/prompt/copy/prefix.md) says not to stretch this exercise beyond a round or two. The [science ledger](../product/breathing-science.md) also makes one or two rounds part of the claim boundary.

**Change:** decide the intended short dose and make default, Moment duration, description and coach offers agree. If retaining a longer practice, it needs an appropriate rationale and description; merely changing “two” to “three” does not resolve the one-minute route.

**Close when:** compare actual configured cycles/duration across exercise, Moment and coach offer. This requires a behaviour decision as well as copy.

### COPY-08 — Watch Health permission says data is never shared while describing sharing

**Evidence:** [project.yml](../../ios/project.yml), Watch `NSHealthShareUsageDescription`, says heart rate lets the iPhone display it, then says “It is never stored or shared.” [PhoneLink.swift](../../ios/OndWatch/PhoneLink.swift), line 58 onward, sends Watch pulse readings to the phone; [PulseRelay.swift](../../ios/Packages/OndCore/Sources/OndKit/Watch/PulseRelay.swift) drives this relay.

**Change:** “önd reads your heart rate during connected sessions and sends it to your paired iPhone to display the live reading.” Describe storage separately and precisely, rather than appending an absolute promise.

**Close when:** generated permission descriptions on both platforms match the actual device-to-device flow. Verify the system permission screen on a device.

### COPY-09 — The privacy page contains material source contradictions

**Evidence:** [privacy.html](../../web/privacy.html) says coach conversations are never stored; [FileConversationStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/FileConversationStore.swift) persists them in `conversations.json`. The page says personal exercise names never reach the coach; [instructions.rs](../../crates/api/src/features/assistant/prompt/instructions.rs), lines 102–109, includes saved exercise names and goals. The same file includes the optional given name. The policy's claim that the model service cannot link conversations is stronger than the absence of an account identifier establishes. Its “one place where you can enter anything” omits chat and exercise text.

**Change:** distinguish local history, server processing and model-provider processing. Proposed factual core: “Coach conversations are saved on your iPhone. To answer a message, the coach receives relevant conversation history and the profile and practice context described below. Saved exercise names and goals can be included.” Add the first name to the precise disclosure. Replace the unlinkability claim with “We do not send your account identifier or leaderboard display name. Text you provide can still contain identifying details.”

Also reconcile the page with the new general AI-sharing choice and separate Health choice in [AssistantConsentView.swift](../../ios/Ond/Features/Assistant/AssistantConsentView.swift) and [ConsentedAssistant.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/ConsentedAssistant.swift). Check permission timing claims against onboarding opt-ins; Mindful Minutes permission can be requested there, not only when a session first needs writing.

**Close when:** use a field-by-field disclosure table covering source, destination, purpose, local retention, server retention and withdrawal. Confirm provider/deployment facts before publishing. This audit establishes contradictions in the local source, not the truth of every provider-retention statement.

### COPY-10 — Profile and leaderboard explanations use false exclusivity

**Evidence:** [ProfileView.swift](../../ios/Ond/Features/Settings/ProfileView.swift) says nobody else ever sees the first name and that only the coach reads the note. Its leaderboard wording and [LeaderboardNameView.swift](../../ios/Ond/Features/Leaderboard/LeaderboardNameView.swift) describe the display name as the only thing other people see. Rankings also show the value being compared. The first name can enter coach context, as COPY-09 demonstrates.

**Change:** “Your first name is used in önd and can be included in coach requests when AI sharing is on.” For the note: “Optional context for your coach. It is included in coach requests when AI sharing is on.” For leaderboards: “Other people see your display name and the value being ranked. Your other profile details are not shown on the board.”

**Close when:** onboarding, editable profile, leaderboard entry and privacy policy disclose the same audiences. Avoid “only”, “nobody” and “ever” unless the complete data path supports them.

### COPY-11 — “Delete everything” needs clear boundaries

**Evidence:** [AccountSection.swift](../../ios/Ond/Features/Settings/AccountSection.swift), lines 181–183, promises erasure from phone, paired Watch and servers. [AccountModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Account/AccountModel.swift) clears server and local stores; Watch identity changes are handed off asynchronously. The privacy page acknowledges backups for up to 30 days. [MindfulMinutesRecorder.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/MindfulMinutesRecorder.swift) writes Health entries but removal only delegates to the app's session store; account clearing does not demonstrate erasure of Health samples.

**Change:** title the operation “Delete account and app data”. Explain removal from the app and active server, Watch clearing when it receives the update, and the separate treatment of Apple Health, subscriptions and backups. Suggested core: “This removes your profile and practice data from önd and our active server. It does not cancel your subscription or remove entries already saved to Apple Health.” Keep the backup detail linked and accessible before confirmation.

**Close when:** verify deletion with an offline Watch and existing Health entries, then ensure the copy describes the observed result. Do not promise immediate remote erasure without an acknowledgement.

### COPY-12 — Purchase and restore failures can finish without useful feedback

**Evidence:** [SubscriptionStore.swift](../../ios/Packages/OndCore/Sources/OndKit/Subscription/SubscriptionStore.swift), lines 233–259, logs general purchase/restore failures and returns to an earlier state. It has specific unavailable/pending states, but no corresponding general failure or distinct restore-outcome copy. This is missing communication, not a request to expose StoreKit diagnostics.

**Change:** provide separate visible outcomes: “We couldn't complete this purchase. Please try again”; “We couldn't restore purchases. Please try again”; “Your subscription is restored”; and “No active subscription was found for this Apple account.” Use the latter two only when the StoreKit result actually supports them. Keep cancellation quiet and approval-pending explicit. Do not claim no charge was made when the result is uncertain.

**Close when:** simulate cancellation, approval pending, unavailable product, interrupted purchase, restore failure and restore with/without an entitlement. This needs state/UI implementation alongside copy.

## Clarity and consistency improvements

### COPY-13 — A paid benefit promises trends over months

**Evidence:** [PlusBenefits.swift](../../ios/Ond/Features/Subscription/PlusBenefits.swift), line 81, says “Health trends over months”. [HealthContextModel.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthContextModel.swift) reads 56 days; [HealthSummaryBuilder.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/HealthSummaryBuilder.swift) derives recent weekly averages and a comparison with earlier readings. The current card does not provide month-by-month exploration.

**Suggested replacement:** “Recent Health trends” / “See recent averages and how they compare with your earlier readings.” Close by comparing the benefit list, feature-specific paywall, website and real subscription metadata with the unlocked screen.

### COPY-14 — Coach recovery copy obscures what is available

**Evidence:** [CoachComposer.swift](../../ios/Ond/Features/Assistant/CoachComposer.swift) uses phrases such as “settling onto this device”, “until that lands” and answering “from its rules”. [fallback.rs](../../crates/api/src/features/assistant/fallback.rs) supplies rule-based recommendations, but chat fallback cannot hold a normal rule-based conversation.

**Suggested replacement:** “Your purchase is active on this device. We're still confirming access to the online coach.” When appropriate: “Chat is temporarily unavailable. You can still use the exercises and basic suggestions.” Match each message to its state; do not imply a timer or automatic recovery path that is not guaranteed. Close by reviewing offline, denied, held and retry states independently.

### COPY-15 — Health guidance points to the wrong screen and overgeneralises

**Evidence:** [HealthTrendsCard.swift](../../ios/Ond/Features/CheckIns/HealthTrendsCard.swift), lines 78 and 96, says session heart data is on Home; it is now in [PracticeHeartCard.swift](../../ios/Ond/Features/Progress/PracticeHeartCard.swift). [privacy.html](../../web/privacy.html) still describes a mark on Home and an average during the session. [PracticeHeartline.swift](../../ios/Packages/OndCore/Sources/OndKit/Journey/PracticeHeartline.swift) includes the recovery window. The Health card also says sleep breathing is slower than waking “for everybody”.

**Suggested replacement:** “See heart rate around your practices in Progress.” Define the averaging window explicitly, including the three minutes after practice. For the comparison: “Sleep and waking readings are taken in different conditions. Compare each with its own history.” Close by matching labels, numbers and missing-data explanations to the current card.

### COPY-16 — “Early research” does not describe every limited-evidence exercise

**Evidence:** [TechniqueWords.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueWords.swift) maps limited evidence to “Early research”. Long Box Breathing's seed says no trial has tested the pattern. The [science ledger](../product/breathing-science.md) defines Limited more broadly than early studies.

**Suggested replacement:** “Limited evidence”. Explain once: “Evidence may be small, indirect, mixed, or absent for this exact pattern.” Retain “Moderate evidence”; do not restore “Well studied”. Close by checking list chips, detail headings and VoiceOver wording against all 13 grades.

### COPY-17 — Users cannot inspect the evidence behind detailed claims

**Evidence:** the exercise seed includes study dates, sample counts and comparative claims, but [TechniqueDetailView.swift](../../ios/Ond/Features/Techniques/TechniqueDetailView.swift) renders explanation/evidence content without the study links maintained in [breathing-science.md](../product/breathing-science.md). “Five minutes today” calls its basis the “strongest daily-practice evidence”, while the ledger is more qualified.

**Suggested replacement:** “Build a regular five-minute breathing habit.” Add a short Sources disclosure with study title, year, link and whether it tested this exact pattern or slow breathing generally. Keep caveats next to benefits. Close through claim-to-source review, including numbers, population, comparison and dose. Adding links does not replace clinical substantiation.

### COPY-18 — Fixed explanatory timings can disagree with adjusted practice

**Evidence:** [TechniqueDetailView.swift](../../ios/Ond/Features/Techniques/TechniqueDetailView.swift) passes the dialled exercise to the rhythm chart and steps, while its reading topics use the base exercise. Catalogue prose describes specific counts, seconds and breaths per minute.

**Suggested replacement:** label fixed descriptions “Default pattern”, or derive the displayed timing summary from the adjusted exercise. Keep research descriptions tied to the pattern that was studied. Close by adjusting 4-7-8 and Coherent Breathing and comparing chart, instructions, explanation, duration and coach offer.

### COPY-19 — Preparation, passage instructions and playful cues need one interpretation

**Evidence:** Cooling Breath's [seed preparation](../../crates/migrate/src/seed/catalogue.rs) offers teeth as an alternative to a curled tongue, while live guidance retains the authored tongue hint. The child register uses a candle metaphor for exhalation while the route uses nasal breathing. [Manner.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/Manner.swift) and [TechniqueWords.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueWords.swift) hold these instructions.

**Suggested replacement:** make cooling guidance support the selected or permitted alternative. Use “Breathe out gently” for a nose-only child exhale, or explicitly approve a different passage before changing it. Review alternate-nostril preparation with a novice: the initial closed side and each switch must be unambiguous. Close by reading preparation and then following only the live cues, including spoken cues.

### COPY-20 — Some server validation messages reach the UI in wire vocabulary

**Evidence:** [ProfileRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Profile/ProfileRepository.swift) and [UserTechniqueRepository.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/UserTechniqueRepository.swift) display rejected message bodies. [profile/service.rs](../../crates/api/src/features/profile/service.rs) names fields such as `intent_note` and `display_name`; [user_technique/validation.rs](../../crates/api/src/features/user_technique/validation.rs) uses backticks, phases and millisecond limits. Most transport and account errors are already translated into safer, useful language; this finding does not apply to all server errors.

**Suggested replacement:** “Keep your note under {limit} characters”, “Choose another leaderboard name”, and “Step {number} must last between {minimum} and {maximum} seconds.” Derive numbers from existing limits. For incompatible client/server values, offer retry/update guidance instead of asking the user to fix an enum. Close by exercising reachable server rejections, not just local form validation.

### COPY-21 — Empty and paused states sometimes assert an unverified cause

**Evidence:** [EmptyCatalogueView.swift](../../ios/Ond/EmptyCatalogueView.swift), phone/Watch Moments and Foundations fallbacks use catalogue/download/server explanations even though the app has a bundled catalogue. [SessionPausedNotice.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionPausedNotice.swift) explains background cue limits in terms of reaching a locked screen.

**Suggested replacement:** “We couldn't load the exercises. Try again.” Use a connection instruction only for a known network failure. For a pause caused by unsupported background guidance: “Practice paused. Open önd to resume.” Explain the sound/background condition in Settings, where there is room. Close by comparing bundled-load failure, refresh failure, empty response, lock and app-switch states.

### COPY-22 — Haptic support instructions are stale

**Evidence:** [support.html](../../web/support.html), lines 66–69, points to System Haptics, asks whether Silent Mode is suppressing haptics, and calls the app setting a strength “dial”. The native app now provides cue modes, a strength choice and phone/Watch previews. The article does not distinguish those platforms or verify its Silent Mode diagnosis.

**Suggested replacement:** start with “In önd, open Settings → Practice and check that your cue mode includes haptics. Use Try the cues to test them, then adjust Haptic strength.” Give a separate Watch path. Confirm exact system-setting advice on hardware before including it. Close by following the article from a fresh installation on each platform.

### COPY-23 — Public history and Health-write promises omit exceptions

**Evidence:** [index.html](../../web/index.html) says history keeps every session. [SessionSummaryLines.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSummaryLines.swift) has “Too short to keep”. [MindfulMinutesRecorder.swift](../../ios/Packages/OndCore/Sources/OndKit/Health/MindfulMinutesRecorder.swift) credits kept guided sessions with permission, but excludes discreet sessions. “Completed sessions” also misses retained practices that ended early.

**Suggested replacement:** “Keep a history of your recorded practices.” For Health: “With your permission, recorded guided practices can be saved as Mindful Minutes in Apple Health.” Explain the short-session threshold where a practice is discarded, rather than making the marketing sentence carry every rule. Close against completed, ended-early, too-short, discreet and denied-Health cases.

### COPY-24 — Welcome copy promises an outcome before explaining the product

**Evidence:** [WelcomeStepView.swift](../../ios/Ond/Features/Onboarding/WelcomeStepView.swift) leads with “Fall asleep faster”. The catalogue and evidence ledger are more careful about subjective outcomes and the evidence for particular patterns.

**Suggested replacement:** “Wind down for sleep, prepare for a demanding moment, or take a quiet break.” Follow with a concrete explanation of guided breathing through movement, sound and touch. Close by comparing onboarding, the local [listing draft](../product/listing.md), website and screenshot captions. Retain specific benefits where the stated evidence supports the exact claim; avoid turning every welcome sentence into a disclaimer.

## Editorial improvements

### COPY-25 — Use product vocabulary instead of implementation vocabulary

**Evidence:** [WristHandoffSheet.swift](../../ios/Ond/Features/Session/WristHandoffSheet.swift) exposes “OndWatch”. [BreathVisualStyle.swift](../../ios/Packages/OndCore/Sources/OndKit/Technique/BreathVisualStyle.swift) offers “Scaling” and “Sweeping”. [SessionGuidance.swift](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionGuidance.swift) says “Just the visuals” even though audio/haptic cue mode is a separate setting. The website calls paid features a “connected layer”.

**Suggested replacements:** “Open önd on your Watch”; “Expanding orb” / “Progress ring”; “Minimal text” / “Phase instructions”; “Optional extras with önd+”. Use “step” for an inhale, hold or exhale; “cycle” for one complete pattern; “round” for repeating the full sequence. Keep exercise names stable. The [listing draft](../product/listing.md) also calls a Moment a “complete guided sequence”, although a Moment selects an exercise and its settings. Prefer “Choose a Moment for a practice suited to your situation.” Close by reading the settings choices without seeing the controls and checking whether they describe the actual choice.

### COPY-26 — Interpolated counts need singular forms

**Evidence:** [PracticeFigures.swift](../../ios/Ond/Features/Progress/PracticeFigures.swift) pairs counts with fixed “sessions”, “minutes” and day labels. [OfferSummary.swift](../../ios/Packages/OndCore/Sources/OndKit/Assistant/OfferSummary.swift) builds “{count} cycles” even for one. Other parts of the app already handle this correctly.

**Suggested replacement:** use shared singular/plural formatting: “1 session”, “1 minute”, “1 cycle”, “2 cycles”. Check zero, one, several, decimal seconds and long durations in visual and accessibility copy. Keep elapsed time distinct from clock time and use explicit units in spoken summaries. Close through representative values, not tests that simply reproduce every string literal.

### COPY-27 — A few progress and fallback lines sound judgemental or certain

**Evidence:** [HomeStateLine.swift](../../ios/Packages/OndCore/Sources/OndKit/Home/HomeStateLine.swift) includes “Nothing this week yet”; the summary labels a short practice “Too short to keep”; [fallback.rs](../../crates/api/src/features/assistant/fallback.rs) uses confident benefit and corrective formulations. These are tone opportunities rather than evidence of a broken flow.

**Suggested replacements:** “A fresh week”, “Practice ended — not saved”, and “You mentioned {goal}. You could try {exercise}.” State the recording threshold beside a discarded result so the warmer title still explains what happened. Keep the quiet voice, specific next action and freedom to stop; avoid streak pressure or exaggerated praise.

## Copy rules to retain

The existing British-English voice, short phase instructions, optional permissions, clearly identified AI coach, free-core explanation, purpose-specific paywalls and explicit missing-data labels are useful foundations. The phone's sequential fade and the Watch clock removal are already implemented; neither should remain on a copy-remediation checklist.

Use **önd** for the app and **önd+** for the subscription. Reserve Apple Health and Mindful Minutes for the named platform/features. Keep live instructions direct: “Breathe in”, “Hold”, “Breathe out”, with a separate qualifier when necessary. Describe what happened before giving a recovery action. Separate a measured number from its interpretation. Describe local storage, server processing and sharing as distinct operations.

## Implementation order and remaining verification

1. **Correct source contradictions:** COPY-08–10, 13–16, 20–23 and 25–26. These have concrete implementation evidence and do not need a new visual direction or price decision. COPY-09 still needs confirmation of provider/deployed-policy facts before publication.
2. **Resolve safety and measurement language together:** COPY-01–07 and 19. Supply this report and both research ledgers to a qualified reviewer. Maximum-hold wording and the scanner example can be removed without inventing a new protocol; final safety guidance and dose need explicit clinical agreement.
3. **Add missing state communication:** COPY-11–12 and the state-dependent parts of 14 and 21. Verify the actual outcomes before promising them.
4. **Finish evidence and editorial work:** COPY-17–18, 24 and 27. Attach sources, distinguish default from adjusted timing, and preserve the app's quiet tone.
5. **Verify release surfaces:** fresh-install phone/Watch permissions; offline Watch deletion; Health retention; purchase/restore/expiry; VoiceOver phase and chart descriptions; smallest Watch/largest text; notifications and Live Activities; real App Store metadata and website deployment. Sample live coach conversations against the approved copy rules.

No shipping strings, timing defaults, clinical protocols, prices or provider settings were changed by this audit. The complete source inventory is finished; copy remediation and release verification are not. No user messages were sent and nothing was published.
