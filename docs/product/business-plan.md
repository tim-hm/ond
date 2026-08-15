# Business plan

The product definition: what we are building, for whom, why it wins, and how it pays for itself. The build order is tracked outside the repository; the name is **önd**, listed on the App Store as "ond breathe" — [naming.md](naming.md) records how it was chosen and what is still open.

## Vision

A breathing app that treats a guided breath the way Apple's Watch Mindfulness app does — one beautiful, haptic-led minute — and then goes where that app refuses to: a science-backed catalogue of techniques for real goals (calm, sleep, energy, focus, reset), personalised by an assistant that learns what you need, on a phone rather than only a watch. Radically simple on the surface, deep on demand, and honest to its core: no ads, no tracking, no dark patterns, no $70 subscription.

## Positioning

The market has a barbell shape and nothing in the middle:

- **Apple Mindfulness (Watch)** — free, gorgeous, haptic-led, and too simple: one technique, no goals, no guidance, no phone experience.
- **Calm / Headspace** — content megaliths at ~$70/year: celebrity narrations, sleep stories, kids' content, and a breathing feature buried under an upsell funnel.
- **Utilitarian pacers** (iBreathe, Awesome Breathing, Breathwork: Paced Breathing) — configurable timers with little craft and no guidance.
- **Exhala** — the nearest competitor: haptic breath guidance on iPhone. No personalisation, no catalogue depth, no social layer.

We sit in the gap: **Watch-grade craft, phone-first, science-led catalogue, AI personalisation, community motivation — at an impulse price.**

**Target users:** stressed professionals who want two calm minutes between meetings; poor sleepers who found 4-7-8 on YouTube and want it guided; Watch Mindfulness users who wished it did more; breathwork-curious people put off by woo or by Calm's price.

## Differentiators

1. **Haptic craft.** Distinct vibration patterns for inhale, hold, and exhale — the phone breathes with you, eyes closed, sound off, and the same sessions live on your wrist in a full Apple Watch app. This is the hero experience, and it is free forever: the paywall never touches the quality of the minute itself, or how many techniques you can point it at.
2. **Science, stated honestly.** Every technique carries its evidence and its safety notes (the seeded catalogue already writes in this voice — see `crates/migrate/src/seed/catalogue.rs`). No mysticism, no medical claims.
3. **Guided personalisation.** Onboarding learns your goals; an LLM tailors recommendations and explains the why. Not a chatbot — a guide with fixed, useful entry points.
4. **User-owned attention.** Reminder intensity is a dial the user sets, and "never" is the default, not an opt-out. Nothing nudges, upsells, or guilts.
5. **Radical privacy.** No ads, no third-party trackers, no data resale. Anonymous identity by default. Privacy is a stated feature, not a settings page.
6. **Honest price.** $1.99 a month or $14.99 a year for önd+, with a 7-day free trial, against Calm's ~$70 a year. Cheap enough to be an impulse subscription, sustainable because what it sells is exactly what costs us money to serve.

## Technique catalogue

Curated, goal-organised, and science-led. Each technique ships with safe defaults and carries its rationale in its summary; an **Advanced** disclosure exposes dials (per-phase durations within evidence-based safe ranges, session length, rounds, haptic/audio intensity). Simple by default, deep on demand.

| Goal   | Technique                   | Pattern                                   | Evidence anchor                                          |
| :----- | :-------------------------- | :---------------------------------------- | :------------------------------------------------------- |
| Calm   | Box breathing (seeded)      | 4-4-4-4                                   | Slow paced breathing lowers acute stress arousal         |
| Calm   | Coherent breathing          | ~5.5 breaths/min                          | HRV-resonance literature                                 |
| Sleep  | 4-7-8 (seeded)              | 4 in, 7 hold, 8 out                       | Extended exhale shifts autonomic balance parasympathetic |
| Sleep  | Extended exhale             | 4 in, 6–8 out                             | Same mechanism, gentler entry point                      |
| Reset  | Physiological sigh (seeded) | double inhale, long exhale                | Stanford 2023 cyclic-sighing study                       |
| Energy | Bellows breath (seeded)     | 1 in, 1 out, rapid                        | Traditional practice; short bouts raise alertness        |
| Energy | Wim Hof-style rounds        | 30–40 fast breaths → retention → recovery | Popular protocol; strongest safety framing in the app    |
| Focus  | Box variant                 | longer holds                              | Attentional anchor; used in high-stress professions      |
| Focus  | Alternate-nostril           | visual-cue-led                            | Traditional practice with modest trial support           |

Safety is part of the product voice: the Wim Hof-style experience is seated-only with prominent warnings (never in water, never driving), and no feature ever rewards pushing a hold to the limit — see the leaderboard design below.

**Breathing foundations.** Alongside the catalogue, the app starts with the decision that matters: practice matters more than perfect. It recommends a comfortable, well-studied exercise somebody will return to, then explains slow breathing, belly and chest movement, nose and mouth routes, pace, fast breathing and holds, comfort, dose, evidence and why önd does not score a breath. Counts and cues are refinements, not pass/fail rules; regular practice has support without implying that every technique is equivalent or that one pattern is ideal. Foundations appear as a short teachable moment in onboarding, as per-session hints, and as a reference the assistant can draw on. The claim boundaries and sources live in [the evidence ledger](breathing-foundations.md).

## Journey tracking & gamification — free

Personal stats are the retention spine: sessions completed, total breaths, cumulative minutes, streaks. The framing rule is **celebrate consistency, never pressure** — "your streak paused", never "you failed".

Competition is opt-in, under a chosen display name, comparable globally or within a voluntarily provided demographic band. Two leaderboard families:

- **Controlled-breath test** — a BOLT-style timed comfortable hold after a normal exhale: an established CO₂-tolerance metric that genuinely improves with practice, and safe to gamify.
- **Consistency boards** — streaks, minutes, sessions.

Deliberately absent: maximal breath-hold contests. Competitive max holds — especially after fast-breathing rounds — are the one place breathwork apps create real physiological risk (blackout), so the app never measures or ranks one.

All of this is free: the growth loop should have zero friction.

## Monetisation

One auto-renewable subscription — **önd+** — via StoreKit 2, sold monthly and yearly in a single App Store subscription group so that moving between the two cadences is a change of plan rather than a second purchase. Both carry a 7-day free trial, and eligibility is one trial per Apple ID per group. No Stripe, no web checkout, no other SKUs at launch. The Small Business Program commission (15%) nets ~$1.69 a month or ~$12.74 a year.

| Tier | Contents |
| :-- | :-- |
| **Free** | The whole app as it runs on the device: every exercise and every protocol, the exercises you build yourself, the session player with haptics and audio, the Apple Watch app, the journal, streaks, schedules and stats, the basics, and writing Mindful Minutes back to Health |
| **önd+ — $1.99/mo or $14.99/yr** | The AI breathing coach; the leaderboards; the health _trends_ the coach reasons from; and the watch and phone working together — a session sent to the wrist, and its heart rate on the phone |

**The rule the paywall is drawn on: what costs us per use is what the subscription sells.** Every LLM call is real money, a leaderboard is a fold across every user on our own hardware, and a health briefing is an LLM call with more in it. Everything else runs on somebody's phone and costs us nothing whether they pay or not — so it is free, permanently, and not as a trial of anything. The server enforces the paid side from the row it verified a StoreKit transaction against, never from anything a request claims: an unsubscribed caller reaches no model at any price and is refused the boards outright.

Below the line, the coach answers from the server's own rules — the same answer everybody gets offline, and a genuinely good one — so nobody meets a wall, they meet a smaller version of the thing.

**What changed, and it is a real change.** Catalogue breadth is free again. The two-tier model sold it, on the reasoning that a $0.99 tier needed something to sell that cost nothing to serve; that turned out to be the argument backwards. Charging for what costs us nothing puts the paywall in front of the growth loop — the technique somebody shows a colleague — for revenue that could be earned honestly from the features that do cost. The catalogue lever survives in the code (`SubscriptionTier.catalogue`, `requires_subscription` in the seed) and every technique is on the free side of it, so a technique that ever does cost something to serve can be priced without rebuilding anything.

The growth loop is therefore untouched and then some: the journal, streaks, the Watch app, custom exercises, and the haptic session player are all free, so the thing people show each other and come back for is not for sale at any point.

## Privacy & trust commitments

Written as testable product rules, not aspirations:

1. No third-party analytics, ad, or tracking SDK ships in the binary — ever.
2. LLM calls go through our backend; the API key never ships to the client, and conversations are not stored for training.
3. Notification intensity is a user-owned dial whose zero state is **never** — the app requests notification permission only after the user moves the dial.
4. Identity is anonymous and device-generated by default; optional Sign in with Apple recovers history on another device, while no account is required for any feature.
5. Leaderboards and demographic comparison are opt-in; display names are chosen, never derived.
6. Any user can delete their data on demand, and deletion is deletion.

## Risks

| Risk | Mitigation |
| :-- | :-- |
| App Review scrutiny of AI + health-adjacent content | Wellness framing, no medical claims, per-technique safety notes (already the seed-data voice); contraindications surfaced in-session |
| LLM cost per non-paying user | Zero by construction: only a subscriber reaches the model, enforced server-side from a verified transaction, with a daily per-caller ceiling on top |
| A generous free tier converts nobody | What is paid is what people ask for once the habit exists — where to start, how they compare, what their body is doing — rather than what they need on day one |
| A purchase step inside onboarding reads as pushy | "Not now" stays prominent, the trial is genuinely free for 7 days, and the 3.1.2 disclosure states the price that follows on both trial surfaces |
| Crowded category, weak discoverability | Distinctive coined name + keyword-carrying subtitle ([naming.md](naming.md)); haptic craft as the reviewable "wow" |
| Competition mechanics undermine the calm brand | Opt-in only, consistency-framed copy, no maximal-hold contests |
| Solo-maintainer scope creep | Every unit of work is independently shippable, and what is deliberately out of scope is written down rather than assumed |
| Full Watch app widens V1 scope | The watch reuses OndKit's platform-neutral session engine; only the haptic mapping and UI are watch-specific |
