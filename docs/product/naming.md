# Naming

The name is **önd**. The App Store listing name is **ond breathe**, and the domain is `ondbreathe.app`.

## How it is written

- **Display: lowercase, with the diacritic.** `önd` — in the app's wordmark, the one subscription (`önd+`), the marketing page, and prose. Coach is a feature, never an entitlement name. The brand is not capitalised or uppercased: `ÖND` is a different word wearing a hat, and the app's whole typographic register is lowercase already.
- **Identifiers: ASCII, always.** `Ond`, `ond`, `OND_` — Swift modules, bundle ids, the proto package, environment variables, directories, filenames, AWS resources. A non-ASCII filename normalises differently across git, macOS and Linux, and the bug that produces is invisible until it is somebody's afternoon.
- **The App Store listing carries the ASCII form** because that is what people type into search.
- **Pronunciation: the plain English reading, /ɒnd/.** The Old Norse is closer to /ønd/, which was never going to survive contact with an English-speaking market. Taking the English reading costs a vowel and buys two things: a name someone can spell from hearing it, and a listing that lands near enough to _and breathe_ for the phrase to register. Near enough is the whole claim — read it as /ænd/ and the spelling stops surviving the trip. The etymology stays true regardless: the coach still tells anyone who asks about the name that it is Old Norse for breath, or spirit.

## The App Store listing

The two fields below, and the hidden keyword field after them, are typed into App Store Connect by hand. Nothing in the repository submits them: `mise run ios:testflight` uploads the binary alone, so there is no metadata file to keep in step and no second copy to drift. The description and promotional text are prose rather than decisions, and live in [listing.md](listing.md).

| Field    | Value                           | Limit |
| :------- | :------------------------------ | ----: |
| Name     | `ond breathe`                   |    30 |
| Subtitle | `Breathwork for calm and sleep` |    30 |

The home-screen label is not one of them. It is `INFOPLIST_KEY_CFBundleDisplayName` in `ios/project.yml`, set once per shipping target — the app, the Live Activity and the watch app — and it keeps the diacritic.

The listing is a compound because the bare word is worse than invisible. An iTunes Search API pass over the US storefront in August 2026 returned, for `ond`: oneD, OneFootball, OBD2 Scanner, OneDrive, and a live listing called **OND** — which, under the uniqueness rule below, makes `önd` alone a rejection risk no subtitle can answer. `ond breathe` also agrees letter for letter with `ondbreathe.app`, which the earlier `ond breath` did not — a name someone hears and then types has to survive the trip.

What the compound does not buy is a ranking for `breathe`. That query returns Calm, Headspace and Breathwrk; head terms are won on download velocity and conversion, not on the name field. The gain is long-tail matching, and the two seconds a stranger spends reading a result list.

Apple indexes the name, the subtitle and the hidden keyword field together and permutes their tokens, so a word spent in one is wasted in another. `ond` and `breathe` are spent. The subtitle spends its budget on `breathwork` — the most winnable keyword in the category — and on two of the goals the catalogue is organised around, because a stranger scanning a list is asking what the app is _for_, not what it _is_. Three alternatives were drafted and rejected, all inside the limit. `Breathing exercises & coach` matches the vocabulary the app itself uses, which is a real argument for it, but it and `Breathwork & breathing coach` both say what the app _is_ and spend two of their few tokens on one stem. `Breathwork, box breathing, HRV` maximises density and reads like stuffing under a lowercase two-word name.

The keyword field is a first pass, 97 of its 100 characters: `box,4-7-8,coherence,pranayama,vagus,anxiety,focus,sigh,resonance,hrv,coach,timer,breathing,stress`. It differs from the two above only in being invisible on the store page, so it can be retuned without changing how the listing reads — but it is version-level metadata like they are, and a change still rides along with a submission for review. `breathing` earns its ten characters despite `breathe` and `breathwork` sitting above it, because Apple's stemming does not reliably join the three.

## Still open

The name is decided and shipping; two checks from the list below have not been run against it, and both should happen before submission rather than after:

1. **Trademark search** — USPTO and EUIPO, Nice classes 9 (software), 42 (SaaS), 44 (health/wellness). This is the check that killed the previous candidate.
2. **App Store Connect name reservation** — the only authoritative claim on `ond breathe`. A reservation costs nothing and holds the name; nothing is reserved yet.

## How we got here

**Breathe** was the internal working name and is unusable as a listing name: at least six live apps use it or a close variant, and Apple's own Watch app owned the word for years (renamed _Mindfulness_ in watchOS 8, partly because the space is so crowded). Nothing answers to it now: the OpenTofu state bucket and the `breathe-tofu` IAM user were the last two holdouts, operator-only and carried for a while as legacy, and both were renamed to `ond-*` once it was clear the inconsistency cost more attention than the migration did. The word survives in the codebase only as a verb, which is the one place it was never a brand.

**Cadence** was carried as far as validation as the market-facing name and taken no further. What validation found, in August 2026, via the iTunes Search API (US storefront) and DNS:

- **App Store**: 51 US apps matched "cadence"; roughly half branded `Cadence: <something>`, none holding the bare name and none a breathing or meditation app.
- **Discoverability**: mixed. "Cadence" surfaces run and bike trackers — running cadence is a core fitness term — so brand searches would have shown competitors above us early on.
- **Trademarks**: Cadence Design Systems is large but in a different field (class 9); _Cadence Health_ (cadence.care, remote patient monitoring) sits uncomfortably close to the health and wellness classes. This was flagged at the time as the check most likely to kill the name.
- **Domains**: `cadence.app` parked for sale at a premium; `getcadence.app` taken by the bike-tracker developer.

## Constraints learned from research

Kept because they apply to any future rename, and to the subtitle:

- **App Store listing names are globally unique.** The name is claimed the moment another developer registers it, and Apple also rejects names confusingly similar to existing apps. The home-screen display name is set separately and need not be unique.
- The winning pattern in the category is a distinctive brand word plus a keyword-carrying subtitle — `Coherence – Breathwork`, `iBreathe – Relax and Breathe` — which is the shape the listing above takes.

## Validation checklist

For any future candidate, in this order — each step is cheaper than the one after it:

1. **App Store search** for the exact word and near-collisions in Health & Fitness and Lifestyle.
2. **Domain availability** — `.app` (requires HTTPS, which we ship anyway) and one fallback.
3. **Trademark search** — USPTO and EUIPO, classes 9, 42, 44.
4. **App Store Connect name reservation** — the only authoritative check.
5. **Say-it-aloud test** — tell three people about the app; if they cannot spell it or find it afterwards, it fails.
