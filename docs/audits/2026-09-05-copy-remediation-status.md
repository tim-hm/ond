# Copy remediation — 5 September 2026

Implementation follow-up to the [complete source-copy audit](2026-09-05-complete-copy-audit.md). The audit records the starting state; this document records the changes and the remaining acceptance work. Changes are local and have not been deployed or submitted to the App Store.

The [release trust validation](2026-09-05-release-trust-validation.md) supersedes this document's research-link and retention status. It records additional claim corrections, privacy-manifest fixes and live AWS evidence, including previously omitted log archives and volume snapshots.

## Changes by finding

| Finding | Implementation | Remaining verification |
| --- | --- | --- |
| COPY-01 | The spoken open-ended hold now says to end while comfortable and when breathing is needed. Removed its maximum-effort instruction and typical duration target. | VoiceOver on phone and Watch; clinical review. |
| COPY-02 | Consent, Basics, fast-breathing warnings, website and coach now say to stop and breathe normally for dizziness, lightheadedness or tingling. Safety consent is version 2 so existing users see the changed instruction. | Qualified review of symptom and escalation wording. |
| COPY-03 | Removed the scanner example and its source comment. | No additional product decision needed. |
| COPY-04 | Removed unsupported reassurance. Pursed-Lip Breathing and both breathlessness Moments now share medical-action guidance; Basics and coach carry the same boundary. | Clinical review of direct-entry and symptom routes. |
| COPY-05 | Check-ins show the latest reading rather than the best/slowest. Results no longer celebrate higher holds or lower rates, and the app recording range is no longer described as a physiological limit. | Physiological leaderboard design remains a product/clinical decision; its ranking rules were retained. |
| COPY-06 | Removed score bands, improvement verdicts and assumed demographic reference ranges from the coach brief. Added explicit measurement limits, symptom escalation and permission to stop. | Live model sampling; authored instructions cannot guarantee every reply. |
| COPY-07 | The default physiological sigh uses two cycles. Its reset Moment requests 15 seconds, which resolves to two default cycles. Coach instructions prohibit increasing its cycle or round count. | Clinical acceptance of the default; existing saved custom timings remain user choices. |
| COPY-08 | Watch Health purpose text explicitly describes sending live readings to the paired phone. | Fresh system permission screen on hardware. |
| COPY-09 | Policy distinguishes local conversation storage from server processing, includes first names and saved exercise names/goals, removes the unlinkability promise, and explains both consent choices. AI consent version 2 includes the corrected disclosure. | Deployed provider/account settings, policy publication and App Store privacy answers. |
| COPY-10 | Profile and leaderboard explanations identify the actual audience and displayed ranking value. Removed claims that the first name or note is seen only by the user/coach. | Check long text on small layouts. |
| COPY-11 | Deletion explains active-server removal, delayed Watch clearing, backup expiry, retained Health entries and separate subscription cancellation. | Offline Watch and Health deletion acceptance. |
| COPY-12 | Purchase failures and restore success, failure or no-subscription outcomes have visible feedback. Cancellation stays quiet; pending approval survives a restore. | Real StoreKit account, approval, restore and expiry flows. |
| COPY-13 | Native and web paid benefits describe recent Health averages rather than exploration over months. | Match live subscription metadata to the local copy. |
| COPY-14 | Coach access notices now distinguish test purchases, refused confirmation and transfer delay, and explain useful recovery actions. | Device/server recovery timing. |
| COPY-15 | Health text points to Progress, explains the existing recovery window and avoids universal sleep-versus-waking comparisons. | Visual and spoken card review. |
| COPY-16 | Limited grades say “Limited evidence”. | Clinical substantiation of the grades themselves. |
| COPY-17 | Removed the “strongest” claim and added an expandable Research sources section to every catalogue exercise. Specific study links are accompanied by scope notes; broader research is identified as such. | Partial: selected sources are a reading trail, not a complete claim-to-paper mapping. Expand links for remaining specific claims during clinical review. Some publisher pages blocked automated access. |
| COPY-18 | Fixed explanatory timings are labelled as the default pattern; chart and practice steps continue to use adjusted timings. | Compare adjusted exercises on device. |
| COPY-19 | Cooling cues allow tongue or teeth; the child's nasal exhale says “Breathe out gently”. | Novice and VoiceOver review of preparation, especially alternate-nostril hand positioning. |
| COPY-20 | Profile and authoring refusals use field labels, steps and seconds; unsupported choices offer update/retry guidance. | Exercise server rejection states through the UI. |
| COPY-21 | Empty states avoid guessing at connectivity; the pause notice gives a direct resume action. | Offline, empty, lock and app-switch states on hardware. |
| COPY-22 | Support now starts with önd's own cue settings and gives separate phone and Watch instructions. Removed the unverified Silent Mode diagnosis. | Follow the instructions on both devices. |
| COPY-23 | Web history and Mindful Minutes promises describe recorded guided practice and acknowledge discreet/short-session limits in the relevant explanations. | Confirm Health write permissions and exceptional outcomes. |
| COPY-24 | Welcome copy describes reasons to practise without promising faster sleep. | First-run layout review. |
| COPY-25 | Replaced OndWatch, Scaling, Sweeping, Just the visuals, connected layer and Add a breath with clearer product wording. Listing copy describes a Moment as a situational choice. | Preference-name recognition on device. |
| COPY-26 | Progress and offer counts use singular/plural forms. Short Moments are described in seconds in coach context instead of rounding down to zero minutes. | VoiceOver and regional duration pronunciation. |
| COPY-27 | Warmer empty-week and discarded-practice headings; discarded results state the recording threshold. Rule-based suggestions no longer promise a benefit or reprimand a goal mismatch. | Beta feedback on tone. |

The sequential phase-text animation and selected icon A are unchanged. No price, leaderboard ranking, data-retention setting or provider model was changed.

## Disclosure cross-check

| Data | Local handling | Server/model handling | User control |
| --- | --- | --- | --- |
| First name, goals, experience, demographic fields and note | Profile retained on device. | Profile stored on the app server; relevant fields enter Bedrock context when AI sharing is enabled. | Edit/clear profile fields; withdraw AI sharing for future requests. |
| Leaderboard display name | Profile retained on device. | Stored on server and shown with the ranking value; not automatically added to model context. | Clear the name to leave boards. Free text elsewhere may still contain a name. |
| Practice and check-in history | Recorded on device and synchronised. | Stored on server; summaries enter permitted coach requests. | Delete supported records or account/app data; withdraw AI sharing. |
| Personal exercises | Cached for use in the app. | Stored on server; saved names and goals enter permitted coach requests. Descriptions are not automatically included. | Edit/delete exercises; withdraw AI sharing. |
| Coach messages and replies | Conversation history is saved on iPhone. | Processed with relevant conversation history; not stored in the app server's database or request logs. | Delete conversations, clear account/app data, or withdraw AI sharing for future requests. |
| Health readings and summaries | Health readings remain in the Apple Health/device context; recent averages are derived on phone. Live Watch pulse is relayed to the paired iPhone. | Only coarse summaries enter coach requests, requiring both Health and AI-sharing choices; no server database/log persistence of those summaries. | Turn either choice off for future coach requests; manage system Health permissions separately. |
| Request metadata and backups | Not a local conversation store. | Existing request metadata logs remain bounded by size; database backups expire after 30 days. Account deletion does not mean immediate erasure of these copies. | Policy explains the limits; confirm deployed configuration before publication. |

Current source selects Claude Haiku 4.5. AWS documents that its newer retention-policy changes do not alter Claude models released before Fable 5. This supports retaining the existing model-specific disclosure, subject to checking the actual deployed model and logging configuration. It does not establish a universal promise for every Bedrock model. [AWS data retention](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html).

## Validation

- `mise run generate` completed, including the bundled catalogue, site figures, icons, protobuf and SQLx cache. `mise run fmt` passed.
- `mise run check:mac` passed: Swift formatting/lint, **1,068 Swift tests across 157 suites**, and both Watch and iPhone simulator builds. The tests cover purchase/restore feedback, pending approval, latest-versus-lowest check-in values, the two-cycle sigh default and spoken guidance.
- Initial Rust lint and SQLx query checks passed. A final lint rerun reached the same startup stall in the API build script. Comment, protobuf, migration, observability, text, Markdown, local documentation-link, dependency, alert, Alertmanager and Loki checks passed.
- The aggregate `mise run check` and `check:diagrams` stopped because they compare generated paths against `HEAD`, which still held the previous catalogue and website copy before this commit. This is not a passing aggregate gate.
- Later Rust test execution and a repeated catalogue export stalled before application code ran. Samples showed only `_dyld_start`: 96 KB for the exporter and 112 KB for the backend integration executable. Retrying did not resolve it; this task's stalled processes were stopped. Rust unit and backend integration results, the remaining infrastructure checks and a clean aggregate rerun still need completion on a working local runtime. No macOS security settings were changed.
- `git diff --check` passed. The catalogue and website checksums remained unchanged during the attempted reproduction check; the interrupted attempt does not establish completed regeneration.

Clinical review, hardware acceptance, live purchases/provider evaluation and publication are separate from compilation and source tests. The full gate must be completed before release.
