# Release scope update — 6 September 2026

## Decision and implementation

The initial release focuses on short, evidence-informed practice, the air animation, sound, touch, and phone/Watch interaction. The conversational AI coach and generated recommendations are removed from the app, API contract, provider dependencies, monitoring, and infrastructure definitions. Future AI features are outside the current subscription promise.

The app now has Home, Moments, Exercises, and Progress. The basics is available in Exercises. Check-ins is available in Progress. Onboarding no longer asks about experience; Settings no longer collects a Coach note or gender. Existing preview profile values and conversations remain subject to account erasure. Legacy conversation and consent cleanup remains wired into deletion.

The two existing subscription products retain their IDs, duration, and introductory offers. Release pricing is £0.99/$0.99 per calendar month and £9.99/$9.99 per calendar year for the UK/US. Other territories use Apple’s equivalents to the US price, with an explicit UK override. StoreKit supplies local display prices and trial eligibility. The annual saving is roughly 16%; the app rounds down to 15%.

Paid benefits are connected Watch sessions and live pulse, recent local Health trends, and optional leaderboards. Core practice, standalone Watch sessions, check-ins, Basics, and the full catalogue remain free. Health summaries are no longer transmitted to any model service.

Current business, listing, privacy, architecture, transport, development, monitoring, and deployment documents reflect the decision. Earlier audits remain historical evidence; removed source links are marked as retired. The original release review’s Coach demonstration and AI margin work are superseded, rather than still open launch requirements.

The shared iPhone vapour shader now mixes its subtle colours through the same three-dimensional flow. A smaller central cloud leaves room for three to five curved wisps. The session player retains one random seed across layout and phase changes; it varies turbulence, wisp count, direction, length, and phase between practices without changing the breathing rhythm. The wisps gather away on full exhale. Home and onboarding use the same shader. The Watch continues to use its separate Canvas renderer.

## Validation and publication

App Store Connect readback confirmed all 175 territories for each subscription, including the exact UK and US prices above. Both subscription descriptions and the English (UK) draft App Store listing now describe the coach-free offer. Version 1.0 remains `PREPARE_FOR_SUBMISSION`; both subscriptions still report `MISSING_METADATA`. Existing group levels differ (monthly 2, yearly 1), as do Family Sharing settings (monthly off, yearly on). These need a release decision.

`mise run generate`, `mise run fmt`, and `mise run check` passed. The gate passed 209 Rust tests, 128 API integration tests, and 1,018 Swift tests, plus Swift/Rust lint, SQLx metadata, generated-artifact reproducibility, configuration checks, and both app builds. Four focused UI checks passed: navigation/Basics/check-ins, first-launch onboarding, fixed instruction placement through holds/pause, and vapour motion/pause. Simulator captures were reviewed for Home, expanded vapour, and the gathered exhale. The latest app was built and installed on Pluto. Automatic launch was blocked because the phone was locked. Physical sound, touch, and Watch behavior remain unverified.

The infrastructure plan validates, but includes an unrelated server replacement because the current Ubuntu AMI lookup selects a newer image. Resolve that replacement before applying the infrastructure change. No API, website, or infrastructure deployment, or App Store submission, was performed.

The generated-artifact checks now compare the working artifacts before and after generation. This checks reproducibility before a commit, including intentional generated changes, instead of rejecting every correct artifact that differs from HEAD. Removing the preview AssistantService deliberately breaks that old contract; the repository’s explicit pre-release protobuf acknowledgement applies before landing.

## Remaining priorities after this change

1. Resolve the focused Progress accessibility audit finding and rerun the relevant UI audit.
2. Complete real Apple sandbox purchase, restore, expiry, and server verification. Confirm App Store subscription metadata, privacy answers, group ranking, and Family Sharing choices; these existing settings were not changed by the pricing request.
3. Verify sound, haptics, animation performance and battery use, Watch wrist-down operation, interruptions, permissions, and reconnection on physical hardware.
4. Obtain qualified clinical review for fast breathing, holds, the parent/child route, and physiological rankings. Decide whether physiological leaderboards belong in the release.
5. Deploy the matching API, website, and infrastructure changes, then verify the live disclosures and absence of model permissions/endpoints. Finish Store metadata and submission screenshots.
6. Verify a backup restore and alert delivery. Test first-practice completion, voluntary return, paid conversion, and proceeds before treating the product as commercially proven.

Shortening the remaining first-run flow and testing a short first practice remain useful experiments. No later AI feature is required to launch this version.
