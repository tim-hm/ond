# Release polish implementation

This is the implementation follow-up to the [release review](2026-09-04-release-review.md). The work is retained locally and has not been deployed or submitted to the App Store. The original review records the starting state, not the state after these changes.

## Implemented

| Area | Result |
| --- | --- |
| Cue recovery | Resume restores the remaining phone haptic envelope and future Watch pulses without replaying the phase boundary or adding paused time to practice. Open-ended holds retain their existing entry-only cue. |
| Phone fallback | Impact generators are prepared before Core Haptics starts. Engine or pattern failures can therefore use the fallback. Debug cue preview includes an engine-failure switch for hardware testing. |
| Audio | Pause stops phase tones as well as bells. Sound-only guidance is available. Settings explains Silent Mode behaviour and offers an unsaved cue preview, with current and rounded sound candidates and a five-minute comfort check. The default sound family is unchanged. |
| Orb | Removed whole-session arcs and independent background motion. The phone core has a softer glow. The Watch uses one core and one fixed reference ring. Hold tint begins at the hold boundary. Side and stacked-breath instructions remain. |
| Phase text | Phone instructions and qualifiers fade out together for 80 ms, then the new words fade in for 140 ms in the same slots. Replacement happens while invisible. New steps cancel pending handoffs; pause, resume and Reduce Motion update immediately. VoiceOver still receives the current phase immediately. |
| Watch | Skippable three-second preparation, explicit runtime-loss pause/retry/end state, bounded startup wait, large-text layout, purpose beside exercise duration, numbered safety points, local guide preference, and current/boundary-only/fewer-pulse auditions, including a five-minute comfort check. |
| Practice graph | Dates, a minutes axis, selected-day values, and one adjustable accessibility element. Zero-practice days represent zero minutes. |
| History | Explicit minute and second units distinguish session duration from its start time. |
| Heart data | Replaced exaggerated miniature bars with numerical ranges and dated readings, including explicit missing readings. The session trace has time anchors and a minimum 10 bpm vertical range, with gaps preserved. |
| Rhythm diagrams | Horizontal labels beneath the drawing with explicit seconds context. Stages remain separate, and geometry still comes from the dialled technique. |
| Accessibility | Phone session and summary have layouts that allow accessibility text sizes to grow. The Watch gives text priority over the orb at accessibility sizes. Reduce Motion retains a stationary core and phase arc. |
| Icon | You selected [A refined ring](../design/icons/refined-ring.svg) on 2026-09-05. Applied its smaller ring, thinner stroke, cyan colour and flat dark tile to the phone appearance layers, Watch launcher and web touch icon. The favicon and complication share its geometry; the favicon uses a darker stroke on light tabs. App-wide palette tokens are unchanged. |
| Privacy and AI | Corrected offline/sync and Health permission wording. Added versioned AI sharing permission, withdrawal, deletion, and a request gate covering recommendations and chat, including automatic opening questions. Health context remains a separate opt-in. |
| Optional permissions | Reminders and Mindful Minutes default off. Skip discards optional changes and does not request their system grants. Existing explicit preferences remain stored. |
| Paid value | Paywall headlines and explanations now match the entry feature, with free exercises stated plainly. Coach has a labelled illustrative example. Prices and entitlements are unchanged. |
| Evidence wording | “Moderate evidence” replaces “Well studied”; this changes the label, not the underlying evidence grade. Foundations now acknowledges optional comparisons with other people and distinguishes a ranking from improvement. |
| UI test isolation | Practice files use a fresh temporary directory for each debug UI-test launch, preventing screenshot fixtures from contaminating empty-history assertions. Release storage is unchanged. |
| UI diagnostics | Added `test:ui:phone:case` for one test on a simulator UUID and `ios:ui:attachments` for exporting result screenshots into a new directory. Both tasks were exercised. |

## Verification before commit

| Check | Outcome |
| --- | --- |
| Swift | 1,061 tests in 156 suites passed; strict lint and formatting passed. |
| Native builds | Phone and Watch simulator builds passed, including the extensions. |
| Rust | 311 tests passed; formatting, Clippy and SQL query checks passed. |
| Backend integration | 163 tests passed; the two real-model-provider smoke tests remain intentionally skipped. |
| Phone UI | 13 of 14 cases pass. The remaining Progress contrast audit still flags its subtitle. Empty-history assertions, Settings, active session, Basics, large-text reading, purchase layout and selection targets pass. The Progress failure was reproduced with the new focused runner. |
| Screenshots | The capture suite passed and exported 13 screenshots. Inspected session, Progress, exercise detail, Home and paywall renders, plus both subtitle failure captures. |
| Website figures | `mise run check:diagrams` passed; figures match the app geometry. |
| Documentation | Markdown, local links and comment checks passed. Existing comment waivers remain unchanged. |
| Catalogue | Regenerated from the seed. A second regeneration left its checksum unchanged. The 2026-09-04 `check:generated` rerun failed only because its HEAD comparison flagged the intentional, uncommitted Foundations copy change in `catalogue.json`. |

One full `CARGO_INCREMENTAL=0 mise run check` completed with exit 0 after earlier compiler delays. Its generation stage preceded the final Foundations edit, so these runs did not establish a clean final gate for the worktree at that time: the explicit generation recheck above records the HEAD comparison. No generated mismatch was found. The phone UI suite runs outside that gate and remains non-green as recorded above.

The subtitle failure capture shows the intended text and background. The palette's composited contrast is 6.23:1; a temporary opaque primary-ink version at 16.61:1 was also rejected. An explicit background did not resolve it either. Both experiments were reverted, and no new audit exemption was added. This suggests an audit interpretation problem, but does not prove its cause. Verify that line on hardware before deciding whether a narrowly scoped exemption is appropriate. Diagnostic captures are in `ios/build/ui-attachments` and `ios/build/ui-contrast`.

The UI suite retains its existing exemptions, including Settings contrast and Dynamic Type checks and some system chrome/snapshot findings. Automated checks cannot establish complete accessibility, tactile comfort, sound quality, wrist-down reliability or production readiness. Watch layouts were source/build reviewed; physical Watch review remains outstanding. Icon A is now applied locally; launcher appearance on hardware remains part of the release review. Live provider smoke tests, real purchases, release signing, deployment and App Store submission were not run.

Phase-text commit verification, 2026-09-05: `check:mac` passed, including strict Swift checks, all 1,062 tests in 156 suites, and both app builds. The focused active-session UI/accessibility case and diagram parity passed. After the release-polish commit, the full gate passed generated-file parity, Rust formatting/Clippy, SQL cache validation and its preliminary documentation/tooling checks. It then stalled while starting the Rust test binaries; those processes remained idle for over four minutes without test results and were stopped. This latest full gate is incomplete, and its backend integration stage did not run. The earlier Rust/integration results above remain historical evidence.

The required generation attempt completed protobuf, catalogue, diagrams and icons, but its SQL cache rebuild was stopped after a compiler stall. Its temporary cache deletions were restored; the subsequent SQL cache validation passed. Formatting completed successfully. Review the new phase-text timing on a device before release; the automated UI case verifies controls and accessibility, not frame-by-frame animation quality.

## Decisions and physical checks needed from you

Icon A follow-up, 2026-09-05: 1,062 Swift tests passed, including the updated palette and geometry checks. Strict Swift lint, the phone build (including the embedded Watch app and complication), diagram parity and Markdown checks passed. Regenerated and visually inspected the Watch and web touch PNGs. The icon assets now add intentional generated changes alongside the catalogue change recorded above. The earlier UI-audit finding remains open; this icon follow-up did not rerun the UI suite or full gate.

1. **Icon hardware review:** A is selected and applied locally. Check its appearance on actual phone and Watch home screens, including system tinting, before release. No further icon selection is needed.
2. **Sound:** in phone Settings → Practice → Try the cues, compare Current and Rounded preview on speaker and headphones, alone and over music, at a comfortable matched perceived loudness. Verify phase recognition and completion. Select a family before changing the default.
3. **Watch touch:** in Watch Settings → Try the cues, compare Current, Boundaries only and Fewer pulses. Verify eyes-closed phase recognition, distinct holds, and comfort after repeated cycles. Choose which patterns deserve a persistent setting and which should be default.
4. **Interruptions:** on an actual iPhone and Watch, pause mid-inhale/exhale, resume, lock the phone, lower the wrist, switch apps, receive an interruption, and return. Guidance must either remain usable or show a paused/recovery state. The debug phone preview can simulate Core Haptics startup failure; verify boundary taps still occur.
5. **Visual comfort and accessibility:** review the quieter orb, phase-boundary tint, dark/light charts, largest text and VoiceOver. Specifically verify the Progress subtitle flagged by the remaining audit finding before changing that assertion. Include the smallest Watch, long phase instructions, left/right nasal guidance, and open-ended holds. Confirm that the preparation is useful and Pause/End remain easy to reach.
6. **Release trust and purchases:** verify the final App Store privacy answers, processor disclosures and release configuration, real-device permission flow, purchase/trial/restore/expiry, and account deletion. Code-level consent enforcement is not App Review approval.
7. **Clinical wording:** arrange qualified review of the tingling/lightheadedness wording, fast-breathing cautions and physiological comparisons before changing clinical guidance. The clinician should resolve the inconsistencies identified in the original report.
8. **Commercial choices:** confirm target audience, candidate pricing, acceptable AI allowance and margin, and the launch distribution route using real usage/cost data. No price, quota, clinical feature or leaderboard was removed on an untested business assumption.

## Remaining product experiments

The [complete source-copy audit](2026-09-05-complete-copy-audit.md) is finished, with a [coverage inventory](2026-09-05-copy-coverage.md). Its 27 findings have a separate [remediation status](2026-09-05-copy-remediation-status.md), covering implementation, validation and remaining clinical/device checks. The non-overlapping phone phase-label transition is implemented; its feel still needs device review with the other visual comfort checks above.

Shorter onboarding, a one- or two-minute first practice, the timing of the trial offer, post-practice reminders, physiological leaderboards, broader palette changes, and acquisition experiments still need the beta observation or product decision specified in the original review. Existing functional architecture was retained. New analytics, pricing changes, deployments and external publication were not introduced.

The cue previews are auditions, not recorded practices. Their alternative sound/haptic patterns do not silently change normal-session defaults. Physical acceptance should cover guided Watch practice, phone-connected practice and discreet bursts separately.
