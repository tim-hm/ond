# ond breathe — release, product, and commercial review

Historical audit: Coach-related findings and pricing were superseded by the 6 September 2026 release decision. Removed source references are marked as retired; the assessment below records the earlier build.

Implementation follow-up: [completed changes and verification status](2026-09-04-release-polish-status.md). The findings below describe the pre-change review.

Reviewed 4 September 2026 against the local workspace at `e5bdd4740`. The workspace was clean at the start. This is an assessment and proposed work, not an implementation or release approval.

## Recommendation

Evolve the app's visual identity around its strongest elements: the breathing orb, quiet colour, readable guidance, and simple session controls. Visual changes are in scope where they make the app more inviting or easier to understand. Keep the free breathing experience. The clearest initial position is a quiet breathing practice for people who want a short break during the working day, with a useful Apple Watch companion. The strongest commercial opportunity is to help those people establish a practice and choose what to do next.

The app already has substantial craft and technical depth. The main risks are inconsistent privacy promises, a long route to the first session, paid benefits that are described more clearly in the code than on the purchase screen, and a very low price relative to the permitted AI usage. Visual refinement should accompany that work, with its effect on appeal and comprehension tested rather than assumed.

I would correct the trust issues and prove the purchase path before a public release. Then use a small beta to test activation and repeat use. The revenue suggestions below are hypotheses to test; this review includes no customer interviews, sales data, or acquisition results.

The expanded review below treats the icon, graphs, motion, sound, touch, and Watch experience as core product work. The first visual prototype explored layout and palette; it did not establish the quality of those interactions. Section 14 gives the additional findings and a concrete sensory design brief.

## Evidence and limits

I traced the phone composition, onboarding, Home, Moments, Exercises, session player, summary, Progress, Coach, Settings, subscription, local storage, sync, Watch session, and backend entitlement and coaching paths. I checked the product plan, listing copy, website, privacy page, and release tooling.

I built and launched the current app on an iPhone 17 simulator running iOS 26.5. I visually inspected Welcome, the personal questions, and permission defaults there. I also inspected the repository's 3 September iPhone screenshots of Home, Moments, Exercises, an active session, Progress, exercise detail, safety, and the light and dark paywalls. Those screenshots are dated evidence, not proof of every current interaction. The older Watch screenshots were not used to certify current Watch presentation.

The public homepage and privacy page both returned HTTP 200 on 4 September. Their pricing and reminder wording were checked against the local files. Apple guidance and competitor pages were checked during this review. App Store Connect configuration, real purchases, physical haptics, production infrastructure, and customer behaviour were not inspected.

Priority means release or business importance here, not security severity. “Confirmed” means the current source or observed UI supports the finding. “Hypothesis” means the commercial effect needs user evidence.

## Five priorities

| Order | Work | Reason | Evidence needed to close it |
| --- | --- | --- | --- |
| 1 | Align privacy statements, AI consent, and reminder defaults | These are trust and App Review risks | The words and actual data flows agree; declining consent sends no AI request |
| 2 | Prove the first session and the paid path on devices | Build success does not prove a usable or honoured purchase | Fresh install, session, purchase, coach reply, restore, expiry, and interruption checks |
| 3 | Shorten onboarding and demonstrate the coach | People must experience value before judging a subscription | Observed first-session completion and repeat use in a small beta |
| 4 | Price and bound coaching from measured cost | The current daily cap does not protect margin | Cost per paying user, including trials and heavy use, against net receipts |
| 5 | Test a focused launch message and distribution route | A polished product still needs an audience | Store-page conversion, retained users, paid conversion, and acquisition cost |

## 1. Privacy statements contradict the implementation — resolve before release. Confirmed

The paywall says practice history stays on the device. Progress uses “Everything else here is on your phone and stays there.” The implementation uploads session history, controlled-pause scores, and resting-rate measurements through `SessionSyncQueue`; both Home and Progress invoke sync. Optional Sign in with Apple enables recovery, but is not what first enables this upload. The privacy policy correctly describes server storage, so the inconsistency is visible across product surfaces.

There is a second mismatch in the Health permission description: “Nothing read is stored or shared.” The assistant request can include summaries derived from Health data, and the backend sends them to Amazon Bedrock. Raw readings remaining on the phone is a narrower claim than nothing being shared.

Use precise statements about availability and transmission. For example: “Your history is available offline. önd also syncs your practice to its server. Sign in with Apple to recover it on another device.” For Health, distinguish raw readings from optional summaries sent to the coach. Revise the source in `project.yml` as well as any generated property list. Check the final App Store privacy answers separately; a local privacy manifest does not prove the submitted answers.

Evidence: [paywall promise](../../ios/Ond/Features/Subscription/SubscriptionPitch.swift), [Progress copy](../../ios/Packages/OndCore/Sources/OndKit/Journey/LeaderboardLines.swift), [sync implementation](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSyncQueue.swift), [Health permission text](../../ios/project.yml), `assistant request` (retired source), [privacy policy source](../../web/privacy.html).

## 2. The coaching path needs explicit AI-sharing consent — resolve before release. Confirmed source gap; App Review risk

I found no explicit consent step identifying the AI processor and the personal data sent before the first coaching request. The chat can send an opening question automatically on entry. The server adds profile, recent practice, and saved-exercise context. A subscription, a safety acknowledgement, a general privacy link, and Apple's Health permission are different choices.

Apple's current guideline 5.1.2(i) requires clear disclosure and explicit permission for sharing personal data with third-party AI. This makes the missing step a concrete submission risk, although this review cannot predict Apple's decision. [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Before the first AI request, explain that the message and recent conversation, relevant profile and practice context, and any enabled Health summaries go through önd's server to Amazon Bedrock. Offer Continue and Not now. Declining should leave breathing available. Record the consent version, allow withdrawal, and cover automatic opening questions as well as typed sends. Keep the Health-summary choice separate and explain its destination beside the switch.

Evidence: `automatic opening question` (retired source), `send action` (retired source), `server context` (retired source), [model configuration](../../crates/api/src/config.rs), [Health switches](../../ios/Ond/Features/Settings/HealthSettingsSection.swift).

## 3. “Skip” does not decline onboarding permissions — fix the behaviour and copy together. Confirmed

The live onboarding screen defaults to daily reminders and enabled Mindful Minutes. The code requests the grants implied by those defaults on both Next and Skip. iOS still controls whether permission is granted; this is an unexpected prompt and default-selection issue, not evidence of permission bypass.

The public privacy page says reminders are off until the user creates one and that the first schedule triggers the prompt. The business plan also promises “never” by default. Both disagree with the current onboarding path.

Restore the stated default of no reminder. Make Skip leave optional grants unrequested. Offer a reminder after a useful first session, with the proposed time visible before asking iOS. The person should understand what action caused each system prompt.

Evidence: [daily default](../../ios/Packages/OndCore/Sources/OndKit/Profile/OnboardingModel.swift), [grant requests](../../ios/Packages/OndCore/Sources/OndKit/Profile/OnboardingModel+OptIns.swift), [Skip handling](../../ios/Ond/Features/Onboarding/OnboardingView.swift), [public wording](../../web/privacy.html).

## 4. Let people breathe sooner — high-value UX experiment. Confirmed flow; conversion effect is a hypothesis

The ordinary free-user flow has five screens: Welcome, You, Permissions, Trial, and Safety. It asks for a name, goals, experience, several preferences, and a subscription decision before delivering the core experience. These questions are mostly optional, but users still have to interpret or skip them. The first-launch UI test checks that the welcome screen appears; it does not complete this journey.

Home is commendably simple once reached. However, its default is five minutes and the quick choices are three, five, and ten. That is a larger initial commitment than the working-day “quick break” positioning suggests.

Test a shorter route: one intent choice, essential safety guidance, then a clearly optional one- or two-minute introductory session. Preserve technique-specific warnings. Present the longer practice as the next choice, without claiming the introductory duration has the same evidence as a studied daily protocol. Defer the name, experience detail, reminders, and trial until they help with a decision.

The countdown currently combines preparation text and the optional pre-session mood question with three seconds to start. Test whether new users can understand preparation without rushing. The Watch starts without the phone's preparation sentence. A brief, untimed preparation state would be especially useful for exercises that need a particular mouth or nose action.

Observe people completing this flow without assistance. Track time to the first breath, whether they finish the intended session, and where they hesitate. Test a trial after demonstrated value against the current early offer; do not assume later always converts better.

Evidence: [onboarding steps](../../ios/Packages/OndCore/Sources/OndKit/Profile/OnboardingModel+Step.swift), [Home defaults](../../ios/Packages/OndCore/Sources/OndKit/Home/HomeOffer.swift), [countdown](../../ios/Ond/Features/Session/CountdownView.swift), [first-launch test](../../ios/OndAppUITests/FirstLaunchUITests.swift).

## 5. The paywall explains the product boundary more than the value — high commercial priority. Confirmed presentation; impact is a hypothesis

The purchase screen is visually coherent. Monthly and yearly plans, trial terms, Restore Purchases, and Not now are present. Keep those strengths.

Its largest message is “Everything that works offline stays free. Forever.” The next sentence calls Plus “the connected layer.” This asks the customer to understand the architecture before deciding why to pay. Several benefits lead with a limitation rather than a useful result. Although the code knows whether the person came from Coach, Watch, Health, or Leaderboards, that context changes the entitlement check rather than the visible pitch.

There is also no exact correspondence between “connected” and “paid.” Reading Health trends and phone-to-Watch communication are local paid capabilities. Creating or editing a free custom exercise requires a server call. Describe the actual feature boundary instead of network use.

Test a context-specific headline using the same shared purchase component. For Coach: “Find a breathing practice that fits your day.” For Watch: “Guide the session from your phone. Follow it on your wrist.” Show one concrete example before the price. Then state plainly that all included exercises and standalone Watch practice remain free. Keep the price, renewal terms, and easy dismissal visible.

Evidence: [shared pitch](../../ios/Ond/Features/Subscription/SubscriptionPitch.swift), [benefits](../../ios/Ond/Features/Subscription/PlusBenefits.swift), [paywall context](../../ios/Ond/Features/Subscription/PaywallPresentation.swift), [custom writes](../../ios/Packages/OndCore/Sources/OndKit/Technique/CachedUserTechniqueRepository.swift).

## 6. Demonstrate a recurring reason to use the coach — high commercial priority. Confirmed UI; proposed behaviour is a hypothesis

Free users see a disabled composer and a general subscription statement. Paid users begin with an invitation to create a conversation. The product plan describes a guide with useful entry points, but this presentation makes users invent the job the coach should do.

Show a clearly labelled example using fictional data: a short request, a short explanation, and an exercise card that can be started. Add useful starting questions such as “I have two minutes before a meeting” and “Help me choose a comfortable pace.” Use the existing exercise-offer path. Avoid suggesting that a generated example is personalised before permission or data exists.

For returning subscribers, test a small review of their recent practice, requested by them: what they practised, what they told the app, and one proposed next session. Separate observed facts from AI suggestions. Do not infer that heart-rate changes prove stress reduction or that more practice caused a medical improvement.

Measure whether a coach visit leads to a breathing session and whether customers return to the coach in later weeks. Message count alone measures use and cost, not value. Keep free breathing generous while making paid guidance easier to understand.

Evidence: `free coach` (retired source), `paid empty state` (retired source), `exercise launch from chat` (retired source).

## 7. The price and AI allowance do not establish a sustainable margin — resolve before promoting Plus. Confirmed configuration; cost scenarios are illustrative

The local offer and public site show $1.99/month or $14.99/year. Assuming enrolment in Apple's Small Business Program, a simplified calculation at 15% commission gives $1.69 per monthly payment or $12.74 per annual payment. Applicable taxes, refunds, regional terms, and all operating costs still matter. Enrolment was not verified. [Apple subscription proceeds](https://developer.apple.com/app-store/subscriptions/)

| Annual subscribers | Approximate monthly equivalent after 15% commission |
| -----------------: | --------------------------------------------------: |
|                100 |                                                $106 |
|              1,000 |                                              $1,062 |
|              3,000 |                                              $3,185 |
|              5,000 |                                              $5,309 |

These are annual receipts divided by twelve, not monthly cash receipts or profit. At this price, approximately 2,826 annual subscribers produce a $3,000 monthly equivalent before other costs. At a hypothetical 3% retained-free-to-paid conversion, that implies roughly 94,200 retained free users. Neither conversion nor required audience is a forecast.

The backend permits 50 model calls per subscriber per UTC day and up to 850 output tokens per chat response. It uses Haiku 4.5 through an EU inference profile. Anthropic's published May 2026 Bedrock list prices show $5.50 per million output tokens for geographic cross-region Haiku 4.5. At 50 calls a day for 30 days, 300 output tokens per call would cost about $2.48 in output alone; the 850-token ceiling would cost about $7.01. Input and cache costs are additional. These are permitted heavy-use scenarios, not observed average bills. [Published Bedrock model prices, page 6](https://www-cdn.anthropic.com/files/4zrzovbb/website/3684c2faafb97418665782cea0001f439f74b1d2.pdf)

Keep the server-side free-tier gate, token accounting, caching, and circuit breaker. Add a monthly spend model that includes free trials, ordinary use, and heavy use. Decide an allowance that the price can sustain and describe exhaustion honestly. Do not solve it only by shortening answers until the coach becomes unhelpful.

Test $2.99/month and $24.99/year as an alternative to the current offer, after improving the paid value demonstration. This is a candidate price, not a recommendation to change it immediately. Compare net contribution per acquired user, refunds, and renewal intention. Avoid an unlimited lifetime AI purchase because it creates ongoing costs without ongoing receipts.

Evidence: `call and token caps` (retired source), [model](../../crates/api/src/config.rs), `token metrics` (retired source).

## 8. Retention should reinforce useful practice — reconsider physiological competition. Confirmed incentives; commercial benefit is unproven

The app already has a thoughtful session summary, an optional before/after mood check, history, and days-practised statistics. Early endings are recorded without failure language. These are good foundations for retention.

Leaderboards rank comfortable holds, lower resting breathing rates, streaks, and minutes. The backend caps hold rewards and floors breathing-rate rewards, which is a meaningful safeguard. It still creates an incentive to change the measurement to obtain a better position. The resting-rate result also celebrates the lowest value. This sits uneasily beside “What you have practised, not how well.” It is not proof of actual user harm, but it is an avoidable conflict in a calm, evidence-conscious product.

There is a direct factual conflict too: the foundations say resting breathing rate is compared only with the person's own earlier measurements. The global and age-band resting-rate boards do compare it with other people. Correct that statement or remove that comparison. [Foundations claim](../../crates/migrate/src/seed/catalogue.rs)

For launch, prioritise personal days practised and a voluntary routine. Consider deferring the physiological boards or keeping those measurements private with neutral wording. If social comparison is retained, trial days practised within a period rather than longest holds, lowest rates, or most minutes. Do not assume a leaderboard is a strong purchase reason without customer evidence.

Make repeat use easy: offer to keep the chosen exercise handy after a useful session and let the person choose a reminder. If adding mood history, make storage and optional Health writing explicit. Existing before/after answers are not a controlled measure of efficacy.

Evidence: [summary](../../ios/Ond/Features/Session/SessionSummaryView.swift), [mood model](../../ios/Packages/OndCore/Sources/OndKit/Health/MoodCheckModel.swift), [leaderboard calculation](../../crates/api/src/features/journey/leaderboard/repository.rs), [resting-rate result](../../ios/Ond/Features/CheckIns/RestingRateTestView.swift).

## 9. Align evidence badges and safety cues with the careful long-form copy — before release. Confirmed wording

The catalogue often explains uncertainty well. But the internal grade `moderate` becomes “Well studied” in the UI. Box breathing and 4-7-8 receive that badge even where their descriptions distinguish general slow-breathing evidence from evidence for the exact counts. A short label can sound more definitive than the explanation beneath it.

Use “Moderate evidence” and “Limited evidence,” or test another plain-language pair with an accessible explanation of what is being graded. Keep the distinction between research on a physiological effect, a symptom, a population, and a particular pattern. This finding concerns presentation of the app's own rubric; it is not a fresh systematic review of every technique.

The safety screen calls tingling “ordinary.” The website and foundations instead advise easing back when tingling occurs. MedlinePlus identifies tingling as a possible symptom of overbreathing. Have the common safety wording reviewed by a qualified clinician and make the action consistent across onboarding, techniques, Watch, and coach. Do not normalise discomfort as evidence that a technique is working. [MedlinePlus: hyperventilation](https://medlineplus.gov/ency/article/003071.htm)

Evidence: [grade title](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueWords.swift), [grade definition](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueVocabulary.swift), [4-7-8 evidence](../../crates/migrate/src/seed/catalogue.rs), [safety text](../../ios/Packages/OndCore/Sources/OndKit/Profile/SafetyConsent.swift), [website cue](../../web/index.html).

## 10. Refine information density and discoverability within the existing design — targeted polish. Visual assessment

Home and the session screen have a strong hierarchy. The quiet colours, serif display text, breathing orb, restrained controls, and dark session surface work together. Preserve them. The persistent Begin action on exercise detail is particularly useful.

Moments and Exercises look related, but their decision models need a quick explanation. The current Moments list begins with duration-led choices such as “Five minutes today,” followed by situations. Test leading with specific situations, while keeping duration visible. “Exercises” can remain the place to choose a known rhythm. Do not remove a tab solely to reduce the count; test whether people can predict where to go.

The Moments screenshot gives each short item a large rounded card and a substantial shadow. This makes a calm browsing screen visually busier than Home. Trial a lighter shadow and slightly tighter card spacing using the existing tokens. Keep readable text and touch targets. The Exercises list is already more compact and should not become denser at the expense of scanning.

History presents pairs such as “8:40 · 5:12” for start time and duration. These are easy to confuse. Use an explicit unit for duration, such as “8:40 · 5 min,” while retaining exact duration in an accessible description or detail view. “The basics” is reachable through Coach even for free users; a novice may assume that tab is paid. Add a relevant link from exercise detail or a brief first-session hint rather than another permanent Home panel.

Evidence: reviewed screenshots (`ios/build/screenshots`), [history row](../../ios/Ond/Features/Progress/SessionHistoryRow.swift), `Coach shortcuts` (retired source), [tab structure](../../ios/Ond/Chrome/AppChrome.swift).

## Visual direction to prototype — warmer, more distinctive, easier to scan. Design hypotheses

The current screenshots show a marked contrast between sparse Home and session screens, and heavier browsing screens with bold headings, rounded cards, and pronounced shadows. My preferred direction brings these surfaces closer together. It should feel welcoming on first use and remain quiet during practice. A visual improvement can help people understand and want the experience, but cannot establish a conversion or retention benefit without testing.

| Surface | Concrete change to explore | What it should improve |
| --- | --- | --- |
| Home | Bring the orb, short invitation, and Breathe action into a tighter visual group. Test a slightly larger orb and reduce the distance between the message and action. Keep the chosen exercise and duration clearly attached to the button. | Make the empty-history screen feel intentional and make the next action immediately clear. |
| Colours and surfaces | Compare the current cool ground with a subtly warmer off-white in light appearance. Keep teal as the main accent and deep charcoal for sessions. Reduce the broad grey card shadows; use a light border or a smaller shadow where separation is needed. | Make the app feel softer while giving the breathing graphic greater prominence. Measure text contrast for each candidate. |
| Typography | Keep serif display text for the welcome, breathing cue, and short reflective messages. Trial less dominant list-page headings, clearer secondary text, and fewer uppercase labels. Keep controls and explanatory text in the system font. | Make Home, browsing, and reading feel like parts of the same app. Improve scanning without shrinking useful text. |
| Moments | Give one relevant suggestion prominence, followed by compact situation-based rows. Test small, consistent illustrations or symbols for bedtime, a meeting, and a short break, using the existing goal colours. Keep the duration and exercise name visible. | Help a new user recognise their situation before learning technique names. Use artwork only where it improves recognition. |
| Coach and paywall | Replace the visually empty disabled-composer presentation with a clearly labelled example exchange and its exercise card. Reuse that example in the offer, with the relevant benefit first and a compact price area below. | Make paid value visible and concrete. Keep renewal terms readable and dismissal easy to find. |

The breathing orb is the best place to develop a recognisable visual signature. Compare its current glossy highlight with a softer light treatment and a cleaner outer ring. Keep its motion driven by the existing session timing; changing easing must not make a phase appear to begin or end at the wrong time. Home's ambient movement and an active session have different jobs, so test them separately. Provide a useful reduced-motion presentation. Apple's guidance supports using colour to clarify hierarchy and adapting animation for motion preferences. [Apple colour guidance](https://developer.apple.com/design/human-interface-guidelines/color?changes=__3), [Reduce Motion](https://support.apple.com/en-us/111781)

Start with two comparable sets of four screens: Home, Moments, an active session, and the paywall. One set should refine spacing, contrast, and surfaces within the current palette. The other can explore the warmer ground and softer orb. Keep the content and features the same between sets so preference is not simply a reaction to different promises.

Ask prospective users what the app does, where they would tap, what is free, and why they might pay before asking which version they prefer. Follow the static comparison with an interactive session; an attractive screenshot can still hide a confusing transition. Check the chosen direction on a smaller phone, at large text sizes, in both appearances, and with Reduce Motion. Do not add an in-app theme picker for this experiment.

Prioritise the Home composition and Coach/paywall demonstration first. Next, refine list surfaces and typography. Broader colour and orb changes should follow the side-by-side comparison. This creates a concrete visual proposal before changing shared tokens across the phone and Watch apps.

**Prototype follow-through — 4 September 2026.** The comparison is implemented in `docs/design/ond-visual-directions.html` for review in the conversation. Direction A, “Cool & clear,” uses a cool ground and brighter cyan orb. Direction B, “Warm & quiet,” uses a warm ground and softer teal orb. Both share content, layout, prices, and interactions across Home, Moments, a breathing session, and the offer. Review controls expose light/dark appearance, 320/390 px phone widths, and a larger text setting; these are prototype controls, not proposed app settings. The other navigation tabs contain minimal supporting previews.

Browser inspection covered Home in both directions, the warmer Moments list and its Sleep filter, session launch/pause/resume/end, and the offer at 320 px with larger text. Switching plans updated the renewal terms, and the trial action displayed a preview confirmation without purchasing. The countdown formatting defect found during inspection was corrected and rechecked. This is browser layout and interaction evidence, not native Dynamic Type, VoiceOver, timing, haptic, StoreKit, or device acceptance evidence. The fragment includes a reduced-motion treatment; it still needs a preference-enabled visual check. Host-provided icons and design controls need checking in the conversation renderer.

My design preference is B: the warmer ground and softer orb feel more welcoming while retaining the core identity. That is an editorial judgement, not user research or evidence of higher conversion. The shipping app and shared tokens are unchanged. Use the comparison to choose a direction before applying it to SwiftUI, and retain the native session engine when implementing motion.

## 11. Keep the architecture; strengthen the release evidence at its boundaries. Source assessment

The shared Protobuf contract, domain package, bundled catalogue, one session timeline, and narrow platform-specific cue implementations are sensible choices. The backend's feature structure, single PostgreSQL datastore, and single deployment are proportionate for a solo product. I found no reason to rewrite the app or add services to pursue launch.

Local reference data is available before a network refresh. Personal stores preserve unreadable bytes instead of silently overwriting the only copy. Session sync has deletion handling and identity-change guards. Subscription refresh handles overlapping reads and purchase updates. These are valuable foundations; this review does not substitute for a security audit or production recovery test.

Concentrate engineering effort on four boundaries:

| Boundary | Release evidence needed |
| --- | --- |
| Phone and Watch runtime | Physical tests for screen lock, foreground/background, audio interruption, wrist-down, pause/resume, and session ending |
| Device and server entitlement | A genuine sandbox/TestFlight transaction accepted by the backend, a real model response, restore on another device, refund, expiry, and unavailable-network behaviour |
| Local and server history | Upgrade, offline session, sync retry, sign-in merge, deletion, and restore without duplicated or resurrected sessions |
| Backup and operating service | Restore a backup into an isolated database and read useful data; verify external outage alerts reach the operator |

Haptics-only phone practice intentionally pauses in the background. Audio mode supports background runtime. Make that distinction clear before users lock the phone; “screen down” can otherwise be read as “screen locked.” The simulator cannot establish haptic quality or that hardware behaviour. The Watch also does not inherit the phone's Sweeping visual preference, and lacks the preparation sentence noted above. Treat these as specific parity decisions, not a reason to mirror every setting.

Refund handling currently depends on client-submitted signed transactions; I found no App Store server-notification route. Client verification remains valuable, but server notifications or reconciliation would make billing state less dependent on the app reopening. This is operational hardening, not evidence that an exploit was reproduced. Confirm actual billing-grace behaviour before advertising it.

The project intentionally has no CI. Preserve that decision and make the manual release evidence explicit: commit/build identity, full gate result, diagrams result, hardware scenarios, purchase proof, and backup restore result. Existing backup integrity checks and external alarms are strengths, but their presence in source is not proof of a successful live drill.

Evidence: [architecture](../../docs/architecture.md), [reference cache](../../ios/Packages/OndCore/Sources/OndKit/Reference/CachedReferenceRepository.swift), [storage recovery](../../ios/Packages/OndCore/Sources/OndKit/Storage/JSONFileStore.swift), [background cue contract](../../ios/Ond/Features/Session/SessionCues.swift), [subscription store](../../ios/Packages/OndCore/Sources/OndKit/Subscription/SubscriptionStore.swift), [Apple verification test boundary](../../docs/testing.md), [deployment and restore](../../docs/deployment.md).

## 12. Make acquisition and learning part of the release plan. Confirmed gaps; tactics are hypotheses

The product plan's claim that the market has nothing between simple timers and large meditation apps is too broad. Breathwrk already markets goal-based exercises, haptics, customisation, and habits. The Breathing App markets a minimal interface, a free starting tier, and background practice. These features alone will not distinguish önd. [Breathwrk](https://www.breathwrk.com/), [The Breathing App's listing](https://apps.apple.com/us/app/the-breathing-app-calm-daily/id1285982210)

Lead with a specific use and demonstrate execution: “A quiet breathing break between meetings.” Make the premium story personal guidance and connected Watch use. Keep evidence honesty and the generous free tier as reasons to trust the product. Avoid making “cheap” the main identity; it attracts a comparison the business may later struggle to sustain.

The public site currently has a Coming soon message and an inactive store badge. That is appropriate before publication, but launch needs a working store destination. If collecting beta interest, make it a separate, voluntary contact request with a stated purpose. Do not silently add marketing contact to the anonymous app identity.

Use three acquisition experiments first: a short real-device demonstration, outreach to small Apple Watch/productivity audiences, and a store-page screenshot sequence about a concrete use case. A video can show timing and handling, but cannot transmit the sensation of a haptic. Invite reviewers to try that part on a device. Do not buy broad advertising before retained-user value and acquisition cost are known.

The screenshot set has strong raw app images. Lead with the session, then the simple start, real-life Moments, free Watch use, personal progress, and a concrete coach example. Ensure that any shown heart-rate feature is identified as requiring compatible hardware and Plus. The current iOS and watchOS deployment targets are 26; assess whether that reaches the intended audience before expanding compatibility. Lowering the target is not an automatic release requirement.

Start measurement with App Store Connect's downloads, product-page conversion, retention, trials, paid conversions, renewals, and churn where available. Apple provides subscription lifecycle reporting. Existing backend metrics can answer service health and model cost. They do not establish a complete screen-by-screen activation funnel. [Apple analytics](https://developer.apple.com/app-store-connect/analytics/), [subscription reporting](https://developer.apple.com/help/app-store-connect-analytics/monetization/subscriptions)

Use observed beta sessions and voluntary feedback for the missing steps first. If adding product analytics later, make a deliberate privacy decision and update the “no analytics” promise; self-hosted analytics are still analytics. Do not log conversations or health context to measure conversion. Treat Apple retention, synced-session activity, and completed-practice retention as different measures with different coverage.

Evidence: [market assumptions](../../docs/product/business-plan.md), [launch link](../../web/index.html), [listing plan](../../docs/product/listing.md), [deployment targets](../../ios/project.yml), [privacy commitment](../../web/privacy.html).

## 13. The current accessibility suite is not green — investigate before release. Confirmed test results

The iPhone UI task finished with exit status 1: 14 tests ran, nine passed and five failed. These were observed on the unmodified app, not introduced by this report. They are not five proven visual defects.

| Failing check | Observed result | Assessment and next action |
| --- | --- | --- |
| Active session accessibility | Dynamic Type partially unsupported; the log identifies the remaining-time label | The player and session words cap growth at `xxLarge`. Inspect an accessibility-size session and provide a layout that preserves essential text and controls. Do not merely suppress the audit. |
| Progress accessibility | Hit area too small; the log identifies `practice-chart` | Check whether the chart is an interactive target or a descriptive accessibility element before changing its hit area or semantics. |
| Settings accessibility | Text clipped; the log identifies “Full guidance” | Inspect the selected-value label at large text and use a layout that fits. |
| Basics opening content | The test could not find “How exact does it need to be?” | That heading is still in the current seed. This is not established as an obsolete-string test. Inspect the rendered/accessibility tree and cached reference data; the cause remains unresolved. |
| Mood touch targets | Measured height `43.99999999999994` against a `44.0` minimum | This is consistent with floating-point rounding. Verify the intended 44-point target, then use a small numeric tolerance; it does not justify enlarging the design by itself. |

Home, exercise detail, paid opt-in gating, large-text reading order, the child Moment route, both paywall-layout tests, exercise filters, and the first welcome-screen test passed. This provides useful evidence, but does not certify every screen, appearance, or device size.

Evidence: UI run log (`/tmp/ond-release-review-ui.log`), [session size cap](../../ios/Ond/Features/Session/SessionWords.swift), [player layout](../../ios/Ond/Features/Session/SessionPlayerView.swift), [test assertions](../../ios/OndAppUITests/OndAppUITests.swift), [mood target assertion](../../ios/OndAppUITests/SelectionControlUITests.swift).

## 14. Refine the sensory experience as a system — a core product priority

The product's distinguishing experience happens during a breathing session, often with the phone put aside. A more appealing paywall cannot compensate for cues that are hard to follow or a Watch experience that feels uncertain. The icon can help recognition, the charts can make practice understandable, and the session can give people a reason to return. Those commercial effects remain hypotheses until tested with users.

This pass traced the current code at `e5bdd4740`, inspected the committed Watch icon and phone screenshots, and built and launched the Watch app on an Apple Watch SE 3 (40 mm) simulator. Live Watch inspection reached first-use safety content and its acknowledgement action. It did not establish the complete current Watch session flow: simulator taps at that action did not advance the screen during this inspection. The 16 August Watch screenshots are historical references only. No sounds were auditioned, no haptics were felt, and no physical Watch behaviour was verified.

### 14a. Icon and symbol: recognisable geometry, weak connection to the in-app experience. Design assessment

The committed Watch icon is a thick, uniform open cyan ring on a dark ground. The phone uses the same open-ring idea through separate light/dark SVG layers in Icon Composer. The complication repeats the geometry in Swift. Inside the app, the main object is a filled, glowing orb. These belong to a related family, but the transition from an open ring to a filled object is not particularly distinctive. The open ring can also resemble a generic loading or activity symbol; that is a recognition hypothesis, not an observed user result.

Develop three vector candidates before replacing the mark: a restrained refinement of the open ring; a simple orb framed by one open ring; and a typographic symbol derived from the ö. My first candidate would be the orb with one open ring because it connects the launcher directly to the practice. Avoid adding several halo layers or tiny details. Test the candidates at actual launcher and complication sizes, in monochrome and tinted treatments, and in a grid among other apps. Ask people to find önd again after a short delay, rather than only which icon they like most. None of these is an approved final icon.

Keep one geometric specification for the phone, Watch, web favicon, and complication. The complication currently restates the ring's radius, stroke, gap, and angle by hand, and its source explicitly notes that no check keeps it aligned. A redesign needs to cover all those surfaces together; a new phone icon alone would leave a fragmented identity. [Icon layers](../../ios/Ond/AppIcon.icon/icon.json), [ring source](../../ios/Ond/AppIcon.icon/Assets/RingLight.svg), [Watch icon](../../ios/OndWatch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png), [complication geometry](../../ios/Packages/OndCore/Sources/OndUI/OpenRingMark.swift).

### 14b. Progress graphs: improve the information before their decoration. Confirmed presentation gaps

The four-week chart shows 28 bars, scaled to the busiest day, without visible dates, a numerical height reference, or a way to inspect a day. The caption gives days practised and the leading goal; it does not let somebody recover the minutes represented by a particular bar. Keep its quiet single colour, but add sparse date labels, a minutes scale or labelled maximum, and a selected-day value. A single chart interaction with next/previous-day accessibility actions is preferable to turning every narrow bar into a tiny button. Label the time range of the totals directly, so the four-week count and lifetime history count are easy to distinguish.

The heart-rate mini-chart is more problematic. It scales each set's lowest and highest readings to a 4–28 point bar-height range, but those numerical bounds are only in the accessibility value. A hypothetical pair of 71 and 72 bpm therefore becomes a short bar and a full-height bar despite a difference of only 1 bpm. A missing reading and the lowest observed reading both use the minimum height, distinguished by colour. This is an avoidable risk of visual exaggeration and ambiguous missingness.

Replace that mini-chart with labelled values or a dot plot with a visible bpm scale, dates, and explicit missing readings. Use a readable minimum vertical range rather than expanding every tiny difference to the full chart. State that these values average the session and three minutes afterwards. Retain the caution against treating lower heart rate as a performance score. If there is too little information to be useful, a short factual summary is better than unexplained bars.

The session heart-rate curve already labels its minimum/maximum and preserves gaps in the readings; keep that work. Add elapsed-time anchors and an explanation when a requested trace has too few samples. Its per-session vertical scaling still needs a visible, comprehensible range. Do not confuse these measurement charts with the technique diagrams, which describe an intended breathing rhythm. [Practice chart](../../ios/Ond/Features/Progress/PracticeChartView.swift), [heart card](../../ios/Ond/Features/Progress/PracticeHeartCard.swift), [heart-rate aggregation and scale](../../ios/Packages/OndCore/Sources/OndKit/Journey/PracticeHeartline.swift), [session curve](../../ios/Ond/Features/Session/PulseCurve.swift), [trace gaps and thresholds](../../ios/Packages/OndCore/Sources/OndKit/Watch/PulseTrace.swift).

### 14c. Technique diagrams: make the instruction easier to read. Design assessment grounded in source

The rhythm figures correctly derive from the dialled exercise and represent fullness over time. Their labels are small, tilted to the curve's slope, and use compact notation such as “in · 4” without a visible seconds unit. This saves space but asks novices to decode both the picture and its notation. Trial horizontal phase labels with explicit units, followed by an optional one-cycle preview. Keep duration proportional to horizontal distance and keep multi-stage practices in separate labelled rows. Do not present the vertical dimension as measured lung capacity.

Use the full diagram on the phone for learning. On the Watch, a short rhythm description or one situational phrase may be more useful than an unlabelled miniature. The shared geometry should remain the source of truth when timing is customised. [Phone diagram](../../ios/Ond/Features/Techniques/BreathRhythmChart.swift), [figure model](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueFigure.swift), [labels](../../ios/Packages/OndCore/Sources/OndKit/Technique/TechniqueFigureDrawing.swift).

### 14d. Orb and animation: reduce competing signals. Confirmed composition; aesthetic hypothesis

The phone combines a scaling core, an extent ring, whole-session progress, hold-colour changes, occasional side/stacked-breath marks, and an independently moving ambient field. The background turns over 46 seconds and swells independently of the breath. Under Sweeping, a phase-progress arc joins the session-progress arc. The Watch uses a related but different composition: its shared glyph scales rings and opacity as well as the core, and its reduced-motion core parks at a different fullness from the phone's session orb.

I would compare a simpler session treatment: one softly lit core for the breath, one quiet frame of reference, a clear phase instruction, and remaining time outside the graphic. Remove decorative background motion during practice. Test whether whole-session progress earns a second circular indicator when remaining time is already visible. Retain special technique instructions, but favour an explicit short label over a subtle mark that has never been explained.

Keep motion driven by the existing session timeline. The current hold tint begins changing before the hold boundary, using an 800 ms crossfade for sufficiently long phases. That can look smooth, but colour is also a phase cue. Test a transition that begins at the boundary and ensure text, sound, touch, and the meaningful visual change agree on when to act. Do not claim timing drift was reproduced: the issue here is the interpretation of a deliberate anticipatory transition.

Reduce Motion already has a meaningful alternative; preserve it. Bring the phone and Watch's visual grammar closer together without requiring identical sizes or decorative effects. The earlier browser prototype is a style exploration and must not replace the native timing or special-technique logic. [Phone orb](../../ios/Ond/Features/Session/SessionOrb.swift), [visual modes](../../ios/Ond/Features/Session/BreathVisual.swift), [ambient motion](../../ios/Ond/Features/Session/AmbientField.swift), [hold transition](../../ios/Packages/OndCore/Sources/OndStyle/BreathGlyphPose.swift), [Watch renderer](../../ios/OndWatch/Features/Session/WatchAirOrb.swift).

### 14e. Haptics: distinguish phase guidance from repeated alerts. Device experiment required

The phone uses a boundary tap and a continuous envelope. The Watch approximates the envelope with pulses spaced roughly 500–850 ms apart. In the current implementation those repeated pulses use `.start`, not `.click`; full-lung holds also use `.start`, and round seams can use it too. This is a concrete reason to test whether texture and boundaries are sufficiently distinct. It is not proof that the pattern feels too strong on the user's hardware. The source records that `.click` was too faint, so blindly reverting every pulse to `.click` would ignore an earlier tradeoff.

Compare the current pattern against two deliberate alternatives on a physical Watch: boundary-led guidance with very few interior taps, and a gentler continuous-feeling pattern with lower pulse density. Preserve distinguishable inhale/exhale and hold cues. Use the same technique and duration, vary one parameter at a time, and ask whether the wearer can follow without looking before asking which feels pleasant. Include the beginning and the end of a five-minute session; first-impression strength does not establish comfort over repeated cycles.

Add a short “Try the cues” preview with phase words in settings or first-use preparation. The phone offers strength settings but no cue audition there; Watch settings currently offers only an on/off switch and a fixed rendering style. If two Watch patterns prove useful, name them for the experience, such as “Gentle” and “Clear,” rather than exposing pulse intervals. Apple recommends designing sound, touch, and animation to communicate a coherent event, and its own examples show that matching meanings does not require identical waveforms. [Apple audio-haptic design](https://developer.apple.com/videos/play/wwdc2019/810/), [Watch controller](../../ios/OndWatch/Features/Session/WatchHapticController.swift), [pulse scheduling](../../ios/Packages/OndCore/Sources/OndKit/Watch/WatchHapticStyle.swift), [phone shape](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionHapticShape.swift), [Watch settings](../../ios/OndWatch/Features/Settings/SettingsView.swift).

### 14f. Cue recovery has specific reliability gaps. Confirmed source paths; prioritise before aesthetic tuning

Both devices cancel haptics when paused, then resume the session clock without restoring the remainder of the current phase's haptic pattern. The next phase boundary restores guidance. The entry-only rule deliberately prevents a misleading duplicate cue, but a wearer can experience several seconds of silence after tapping Resume. Design an explicit resumption contract: a brief preparation followed by a clear phase boundary, or a remaining-phase cue supported by the engine. Do not restart a full inhale cue in the middle of an exhale or silently change recorded duration.

There is also a concrete phone fallback defect: on supported hardware, if Core Haptics engine creation/start fails, `prepare()` logs the error without preparing impact generators. `play()` then calls `playFallback`, which returns because its generator dictionary is empty. The same unprepared fallback is used if pattern creation/playback fails after a successful engine start. Prepare fallback generators for these paths and test with an injected engine failure. This is source-confirmed, not a reproduced hardware failure.

Watch extended-runtime refusal, expiry, and invalidation are only logged. The model is left running, so there is no user-facing distinction between a session with wrist-down runtime and one that has lost it. Expose runtime state to the session and provide a clear recovery or pause state when the guarantee is lost. Physical tests must cover wrist-down, switching apps, interruptions, and returning to the session. [Resume contract](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionModel.swift), [phone fallback](../../ios/Ond/Features/Session/HapticController.swift), [Watch runtime](../../ios/OndWatch/Features/Session/ExtendedRuntime.swift).

### 14g. Sounds: compose a calm, learnable cue family and make it auditionable. Source assessment; sound quality unverified

The current phase cues are short sine tones: inhale 440 Hz, exhale 330 Hz, full hold 587 Hz, and empty hold 262 Hz. Stage and round bells add layered notes, and completion uses a rising three-note motif. A four-pitch code is learnable, but it needs teaching; choosing “Haptics & sound” does not explain what each sound means. The visual orb suggests softness and continuity while the sound design communicates primarily through discrete pitches. Whether that mismatch is audible or unpleasant requires listening.

Compare the current set with one restrained, softly rounded cue family. Give inhale and exhale clearly different contours; keep holds quieter and brief; reserve the most distinctive cadence for completion. Avoid adding background music or many sound packs before the basic cues work. Evaluate at matched perceived loudness on the phone speaker and headphones, both alone and over existing music. The app already mixes with other audio.

The default mode includes sound and configures `.playback`, so cues can sound with the phone's silent switch enabled. Make the selected sound mode visible before the first session and offer a short audition. Add an audio-only option if users want headphone guidance without vibration: the current enum has combined, haptics-only, and visual-only modes. `SessionAudioPlayer.pause()` pauses the silence loop and bells but leaves the phase players untouched, so a short cue can finish after Pause; include that in the cue-stop contract and listening checks. [Audio and tone definitions](../../ios/Ond/Features/Session/SessionAudioPlayer.swift), [synthesis](../../ios/Packages/OndCore/Sources/OndKit/Session/ToneSynthesizer.swift), [cue modes](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionCueMode.swift), [defaults](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSettings.swift), [practice settings](../../ios/Ond/Features/Settings/PracticeSettingsSection.swift).

### 14h. Watch UX: optimise for choosing quickly and practising without looking. Source and limited simulator assessment

Keep the recent/recommended shelf: the app already has a direct route to a familiar practice, so it does not need another navigation rewrite. Improve first use and the unfamiliar-exercise route. The 40 mm first-use safety page requires several scrolls before the acknowledgement button. Preserve the cautions, but edit and group the text for a wrist and keep the most consequential guidance easy to scan. The exercise carousel displays a name, duration, diagram, and play button but little help choosing an unfamiliar technique. Add one short purpose or situation where it improves that decision.

A normal Watch session starts immediately from the tap, with no preparation/count-in. Trial a brief, skippable readiness cue before the first inhale, particularly for unfamiliar rhythms. Keep Pause and End directly available. They already have 44-point outer hit frames; their small 34-point visible discs are a discoverability question, not proof of undersized touch targets. Do not hide them behind a menu just to achieve visual emptiness.

The Watch's phase word is constrained to one line and can shrink to 60%; its orb also has a minimum size even if the remaining space is smaller. Run the actual largest text settings on the 40 mm case, including long instructions, nasal-side hints, and open-ended holds. The current phone “Sweeping” preference is not a Watch preference; decide explicitly whether this is device-specific or shared instead of letting the difference remain implicit. Reduce Motion must continue to work independently on both devices.

Treat guided Watch practice, phone-connected practice, and discreet burst sessions as distinct flows. The discreet screen already avoids a decorative orb and shows elapsed time, burst count, and End; preserve that focus. Its permission/runtime journey needs its own acceptance test rather than being inferred from a normal session. [Watch entry](../../ios/OndWatch/RootMenuView.swift), [carousel](../../ios/OndWatch/Features/Techniques/TechniqueCarouselView.swift), [session layout and start](../../ios/OndWatch/Features/Session/SessionView.swift), [discreet session](../../ios/OndWatch/Features/Moments/DiscreetSessionView.swift).

## Sensory design brief and order of work

| Order | Concrete deliverable | How to judge it |
| --- | --- | --- |
| 1 | Repair cue fallback and define pause/resume/runtime-loss behaviour | Injected failure tests plus physical interruption and wrist-down checks; users always know whether guidance is active |
| 2 | One short session with coordinated orb, sound, and haptic candidates | Can a new user follow inhale, exhale, hold, resume, and finish without repeatedly checking the screen? |
| 3 | Revised Watch start, preparation, and session layouts on the smallest case | Quick familiar start; understandable unfamiliar choice; readable large text; immediate access to Pause and End |
| 4 | Labelled practice and heart-rate chart candidates | Can people state what was measured, when, and how much without guessing from colour or bar height? |
| 5 | Three vector icon candidates, including a refined existing mark | Small-size recognition, recall, monochrome clarity, and connection to the session visual |

Keep the cue grammar consistent: expansion means inhale, contraction means exhale, stillness means hold, and a distinct final cadence means the session has ended. Do not make louder or faster cues mean that someone breathed “better.” Free sessions should receive the same quality of motion, sound, and touch as paid sessions; their quality is the evidence on which users will judge the product. The likely paid opportunity is useful guidance and dependable connected practice, not charging to remove roughness from the core experience.

## Suggested delivery sequence

| Stage | Deliverable | Decision |
| --- | --- | --- |
| Before beta expansion | Correct data/permission claims; add AI consent; align safety copy; investigate accessibility failures | Can people use and pay for the app with an accurate understanding of it? |
| First beta cycle | Observe 8–12 new users across phone-only and Watch use; include large text and VoiceOver | Can they start unaided, understand the controls, and find a useful session? |
| Second beta cycle | Try shorter onboarding, a coach example, and optional reminder after practice | Do more people complete a first session and practise on several days? |
| Commercial pilot | Compare current and candidate pricing across suitable cohorts; measure cost and trial-to-paid behaviour | Does each acquired payer contribute enough to cover service and acquisition costs? |
| Public launch | Complete the manual release gate, device checks, purchase proof, store assets, and live download link | Is the shipped build the one that was tested and advertised? |

Use beta results to set targets rather than borrowing arbitrary category averages. Track the full chain: store visitor → install → first useful session → repeated practice → trial → paid renewal. A free user who builds a habit is valuable even if they never subscribe; the business still needs evidence that enough people value the paid guidance.

## Validation record

- `mise run ios:sim:phone`: passed, including the phone build and embedded targets; installed and launched on the simulator.
- `mise run test:swift`: passed, 1,051 tests in 155 suites, exit status 0.
- `mise run test:ui:phone`: failed, nine of 14 tests passed and five failed; exit status 1. Findings and distinctions are recorded above. Result bundle (`/Users/tim/Library/Developer/Xcode/DerivedData/Ond-bcwvoujzneahkigsddplwkwggnmd/Logs/Test/Test-Ond-2026.09.04_22-04-03-+0100.xcresult`)
- Current simulator inspection and dated screenshot review as described above; public homepage and privacy returned HTTP 200.
- Expanded sensory/Watch review: `mise run ios:sim:watch` built successfully but initially could not install because no Watch simulator was booted. After opening the SE 3 (40 mm) simulator, the same task passed, installed, and launched the current Watch app. Live inspection was limited to first-use safety content; current session behaviour was assessed from source. Watch build and launch log (`/tmp/ond-watch-review-build.log`)
- No application code, price, deployment, or App Store settings changed. No full `mise run check`, Rust/database integration suite, release build, real purchase, physical-device acceptance test, or production backup restore was run for this report.
