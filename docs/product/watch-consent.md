# The consent on the wrist

The watch is a full session surface, not a remote: somebody can breathe on it before the phone app has ever been opened. The safety terms are a wall on the phone, so a wrist that skipped them would be a session nobody agreed to. This document is the decision behind the wrist's own consent — what it asks, why it is shorter, when it is skipped, and what happens when the phone's agreement goes away.

The words are [`SafetyConsent.swift`](../../ios/Packages/OndCore/Sources/OndKit/Profile/SafetyConsent.swift); the record and the rule are both [`SafetyConsentStore.swift`](../../ios/Packages/OndCore/Sources/OndKit/Profile/SafetyConsentStore.swift), whose `needsConsent(whenAnotherDeviceAgreedTo:)` is the decision; the screen is [`WristConsentView.swift`](../../ios/OndWatch/Features/Onboarding/WristConsentView.swift). Every rule below is pinned by [`WristConsentTests.swift`](../../ios/Packages/OndCore/Tests/OndKitTests/Watch/WristConsentTests.swift).

## What the wrist asks

Exactly what the phone asks. The screen renders `SafetyConsent.current` — the title, the intro, the five hazards and the agreement word — and nothing else. No new sentence is written for the small screen.

This is the one rule the whole design hangs from. The two screens are the same agreement, so they must carry the same words. A shortened wrist copy would be a second set of terms, and the record `SafetyConsentStore` keeps would then prove a version of the terms that no screen ever showed.

## Why it is shorter than the phone's wall

It is shorter in layout, not in content. The phone's wall (spec §10) is a title in the display face at 36pt, an intro paragraph, five hazards in a hairline-separated stack, and a separate action pinned to the bottom inset. The wrist keeps all of that text and changes three things:

**One scrolling column, and the button at the end of it.** A watch screen holds about two hazards at a time. A button pinned to the bottom would sit over the terms from the first frame, which is a button offered before anything has been read. Putting it after the last hazard makes agreeing require scrolling past all five.

**The agreement word is the button.** The phone has room for a separate control and its label; the wrist does not. `SafetyConsent.agreement` — "I understand" — is what the button says, so the press and the sentence it agrees to are one thing. There is no checkbox: a checkbox plus a button is two taps for one decision, and the second one would have no words of its own.

**Nothing else is on the screen.** No back, no skip, no title bar. The wrist reaches this screen instead of its front door, not in front of it, so there is nothing behind to go back to. A session the phone orders is the one other way to a session, and `WristOrderModel` declines it while the terms stand — declines rather than holds, because a sheet on the phone is waiting on that answer.

## Exactly when it is skipped

The wrist asks when **both** of these are true:

1. This watch holds no agreement of its own that covers the current terms — `SafetyConsentStore.needsConsent`.
2. The phone has not told this watch about an agreement that covers them either.

The phone's agreement travels in `WatchHandoff`, the one `applicationContext` dictionary the pairing already carries. It is the version number that was agreed to, not a flag, so the wrist compares it against its own copy of the terms: an install whose terms have moved to version 2 asks again even though the phone agreed to version 1. That is the same comparison `SafetyConsentStore.needsConsent` makes, applied to the phone's record.

Two consequences follow from carrying a version rather than a flag, and both are deliberate:

- A watch that has never met its phone asks. A context that never arrived, one from a build too old to carry the key, and one that arrived unreadable all read the same way: nothing is known, so ask. Asking somebody twice costs a screen. Not asking them costs the agreement.
- **Skipping does not write a record on the wrist.** The wrist records only what somebody agreed to on the wrist. Back-filling an agreement from the phone would put an invented timestamp against words this person read somewhere else, and `AgreedSafetyConsent` exists precisely so a consent record can answer "which words, and when".

Consent does not travel the other way. Agreeing on the wrist does not satisfy the phone's wall, because that channel (`sendMessage` / `transferUserInfo`) is lossy by design and carries no state. Somebody who starts on the watch and then opens the phone reads the terms once more. That is the cheap direction of the same trade.

## What happens when the phone withdraws consent

There is one way the phone's agreement goes away: **delete everything**. `SafetyConsentStore.erase` is in the phone's deletion list, so the record goes with the practice, and the phone puts its own wall back.

The wrist follows, and by one rule rather than two:

- The next context the phone sends carries no agreed version, because there is no longer a record to read one from. Absent means unknown, so the wrist stops leaning on the phone.
- The same deletion also mints a fresh identity and marks the context `erasesPriorHistory`, which empties everything this wrist holds about the person who was deleted. The wrist's own consent record is in that list, beside the sessions.

So after a deletion the wrist asks again, whether it had leaned on the phone's agreement or made one of its own. This is the honest outcome: the deletion's promise is that nothing of that person is left on either device, and a consent record is a dated statement that a named person agreed to something. The next person to raise this wrist has agreed to nothing, and is asked.

Nothing else withdraws consent. There is no toggle that un-agrees, on either device, for the reason `SafetyConsentStore` gives: the record is written once and never edited.
