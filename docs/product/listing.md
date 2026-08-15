# App Store listing

The long-form store copy. The name, subtitle and keyword field live in [naming.md](naming.md), because each of those is a decision with an argument behind it rather than a piece of prose; this file holds the two fields that are writing.

Nothing here is submitted by the repository. `mise run ios:testflight` uploads the binary alone, so every field below is typed into App Store Connect by hand — which is exactly why they are written down: a field that exists only in a web form has no history, no review, and no second reader.

## The fields

| Field            | Limit | Editable without review |
| :--------------- | ----: | :---------------------- |
| Promotional text |   170 | **Yes**                 |
| Description      |  4000 | No                      |

Promotional text sits above the description on the store page and is the only copy that can change between submissions. That makes it the right home for anything seasonal, anything responding to beta feedback, and anything not yet worth a review cycle. It is also the first thing to go stale, because nothing forces it to be revisited.

## Promotional text

```text
Guided breathing for iPhone and Apple Watch. Haptics carry the rhythm, so you can put the screen down and stay with the breath. Evidence presented with its limits.
```

## Description

The opening line is what the store shows before the reader taps "more", so it carries the claim on its own and is short enough not to be cut.

```text
Guided breathing, grounded in evidence.

önd is a focused breathing practice for iPhone and Apple Watch. Distinct haptics mark each inhale, hold and exhale, so you can put the screen down, close your eyes, and stay with the breath.

BUILT FOR PRACTICE
Pick a Protocol when you want a complete guided sequence and would rather not decide what comes next. Choose an Exercise when you already know what you need. Every included pattern is available from the start — box breathing, 4-7-8, coherence and resonance pacing, physiological sighs and more — and you can build your own when a different rhythm suits you better.

ON YOUR WRIST
The Watch app is a place to practise, not a remote control. Start an Exercise or Protocol without reaching for your phone. One clear breathing shape, phase-specific haptics, deliberately minimal controls. Sessions carry on when the display rests, and standalone Watch practice is part of the free app.

PROGRESS WITHOUT PRESSURE
Your journal, schedules, streaks and simple statistics are there when they help, and out of the way when they don't. Ending a session early is recorded honestly, never treated as a failure.

EVIDENCE WITH LIMITS
Slow-paced breathing reliably changes cardiovascular measures such as heart-rate variability while you practise. Reported effects on stress, mood and anxiety are promising, but smaller and less consistent across studies, and longer-term effects are less certain. No single pace or technique has been shown to be ideal for everyone.

That is how önd presents it: what was studied, what changed, and where the limits are. A comfortable breath matters more than a perfect count.

QUIET BY DESIGN
No ads. No third-party trackers. No feed to scroll. The session screen does one thing.

önd+
An optional subscription adds a coach informed by your goals and practice, breathing, heart-rate and HRV trends, global and age-band leaderboards, and connected Watch practice with live heart rate. Everything else stays free, including the full catalogue and standalone Watch practice.

A NOTE ON SAFETY
Breathing exercises are not a treatment for any medical condition. If a pattern leaves you dizzy or light-headed, ease back or return to normal breathing. If you are pregnant, or live with a heart or respiratory condition, speak to a clinician before starting.
```

## Why it reads the way it does

- **The brand stays lowercase, in headers too.** The section headers are capitalised for scanning; `önd+` is not. `ÖND` is a different word wearing a hat, and [naming.md](naming.md) settles that.
- **The evidence section undersells, deliberately.** It restates the site's own hedge — promising, but smaller and less consistent across studies — rather than the strongest reading. That is the honest summary, and it is also what keeps the listing clear of guideline 1.4.1, which is where a breathing app promising to treat anxiety gets rejected.
- **The safety note is not boilerplate.** Hyperventilation is the one way this app can hurt somebody, and the catalogue already fences fast breathing off non-energising routes. A listing that omitted it would be quieter about risk than the app is.
- **Free and paid are stated plainly.** The full catalogue and standalone Watch practice are free; the four `önd+` benefits are the paywall's own, in its order. Copy that implied the catalogue was paid would be a mismatch a reviewer can see from the screenshots.

## The other fields, and where their values come from

| Field              | Value                            |
| :----------------- | :------------------------------- |
| Support URL        | `https://ondbreathe.app/support` |
| Privacy policy URL | `https://ondbreathe.app/privacy` |
| Marketing URL      | `https://ondbreathe.app`         |
| Copyright          | `2026 Tim Holmes-Mitra`          |

The first two are required to submit and are served by the marketing site, which `mise run deploy` rsyncs — so the pages a reviewer opens and the pages this repository holds cannot drift apart without a deploy.

App previews are optional and there are none. Screenshots are required, and because the submission embeds a watch app, Apple Watch screenshots are required alongside the iPhone set.
