# Business plan

## Release focus

önd is a short breathing practice for iPhone and Apple Watch. Its value is the experience of practising: responsive air animation, clear timing, carefully matched sound and touch, and a Watch interface that works with the screen resting. The App Store name is **ond breathe**; [naming.md](naming.md) records the identity.

The initial release has no conversational AI coach, generated recommendations, or model-provider requests. Future AI features need their own product case, cost model, consent design, evidence boundaries, and release decision. They are not promised as part of today’s subscription.

## Who it serves

People who want a short pause between tasks, a comfortable evening routine, or a breathing rhythm they can follow without watching a timer. Moments provides a starting point; Exercises provides the full catalogue and personal rhythms. Goals organise the choices locally. The basics explains comfortable practice, with sources and limits.

The differentiation is a product hypothesis: consistent craft across phone and wrist, a distinctive breathing visual, and useful practices without pressure. A polished interface alone does not prove acquisition, retention, or willingness to pay.

## Free and paid

The core practice remains permanently free: every included Exercise and Moment, custom exercises, air animation, session sound and haptics, standalone Watch practice, Progress and History, check-ins, reminders, The basics, and writing Mindful Minutes to Apple Health.

One optional subscription, **önd+**, adds connected phone-and-Watch sessions with live pulse, recent local Health trends, and optional leaderboards. These features support useful additional experiences and ongoing development. Subscription value does not depend on model usage or a promise of future features.

| Storefront     | Calendar month | Calendar year |
| :------------- | -------------: | ------------: |
| United Kingdom |          £0.99 |         £9.99 |
| United States  |          $0.99 |         $9.99 |

App Store Connect readback on 6 September 2026 confirmed these exact UK and US price points and all 350 monthly/yearly regional prices. Other territories use Apple’s US-price equivalents, with an explicit UK override. Both existing product IDs stay unchanged: `xyz.holmie.ond.plus.monthly2` and `xyz.holmie.ond.plus.yearly`. Both plans retain the seven-day introductory trial for eligible subscribers. The app displays the price and eligibility returned by StoreKit; it never guesses a local price when products cannot load.

Annual pricing is approximately 16% below twelve monthly payments. The paywall rounds the saving down to 15% so it never overstates it. Gross list-price income is not proceeds: taxes, Apple commission, trial conversion, refunds, plan mix, and regional prices affect actual revenue. The private MRR metric uses the US monthly list price as a labelled estimate; it is not an accounting report.

## Experience and evidence

A comfortable breath matters more than matching a count. Technique evidence and safety notes remain visible on each exercise; [the evidence ledger](breathing-foundations.md) defines claim boundaries. The basics lives in Exercises. Optional check-ins live in Progress and describe personal observations, not a diagnosis or proof that practice improved someone’s health.

Leaderboards remain optional under a chosen display name. Physiological rankings still need a separate release decision and qualified clinical review; a ceiling does not prove that a competitive hold is safe. Consistency and returning willingly are better commercial success measures than longer breath holds.

## Trust

No ads, third-party trackers, or data resale. Practice starts without signing in. Optional Sign in with Apple supports history recovery. Reminders are off until chosen. Health access is a local opt-in and no Health summaries are sent to an AI provider. Existing preview conversations can still be removed through account and app-data deletion. The public privacy policy describes retention and backup limits.

## Release and commercial priorities

1. Verify purchase, restore, expiry, cancellation, and server verification with Apple sandbox transactions.
2. Validate animation performance, haptics, sound, Watch background behaviour, and interruptions on physical devices.
3. Resolve the outstanding Progress accessibility finding and finish clinical review of higher-risk practices and rankings.
4. Publish matching app, backend, website, and Store metadata; verify the live product rather than inferring publication from a merge.
5. Test whether new users complete a short first practice and choose to return. Review acquisition sources, subscription conversion, retention, refunds and support themes without introducing tracking SDKs.
6. Reassess price and paid benefits against observed retention and proceeds. The low launch price is a deliberate hypothesis, not proof of sustainable revenue.
