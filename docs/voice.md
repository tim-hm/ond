# Voice

How a session comes to say "Breathe in" out loud, and what has to be true for it to keep saying the right thing.

## Nothing runs on the phone

The app's spoken vocabulary is closed. A person authors an exercise's _name_ and _summary_, and neither is ever spoken — the cues are a fixed dozen lines per language, composed from `Breath` and `PhaseKind` in `ios/Packages/OndCore/Sources/OndKit/TechniqueWords.swift`. So the whole corpus is a few hundred characters per voice.

That is what makes a hosted model the cheap answer instead of the expensive one. The clips are rendered once, when the copy changes, and committed as AAC. Three things follow:

- **A service outage cannot break a build.** The audio is in the tree; nothing at build or run time asks ElevenLabs for anything.
- **Nobody needs a key to work on the app.** Only the person changing the words re-renders.
- **`playsInBackground` keeps its argument.** Playing a decoded clip is still just audio, which is what `UIBackgroundModes: audio` covers. Running inference on a locked phone is a different claim, and it is the claim App Review reads.

It replaced a local Kokoro-82M pipeline, abandoned for quality rather than size: Kokoro could not say a word-final /θ/, so "mouth" and "mouse" came back with the same spectrum in three of its four voices.

## The manifest is the source

One TOML per **language**, in `crates/toolkit/voice/` — not one per accent. `cues` is a property of the language and `variant` is a property of the voice, so eight readers of four Englishes share one table of words rather than carrying four copies free to disagree.

```toml
model = "eleven_multilingual_v2"

[[voices]]
slug = "faye"                      # ours: the folder, and the key the setting persists as
voice = "wOPou4MhRIYEqQHVxjmp"     # ElevenLabs' id
title = "Faye"                     # what the picker shows
variant = "en-GB"                  # orders the picker; `SessionVoice.region` names it
default = true                     # exactly one voice, checked at render
speed = 1.0                        # 0.7 is the service floor; 1.2 the ceiling
stability = 0.85

[cues.short-in]
text = "In"                        # the copy — held to `Breath.spoken` by the tests
say = "In."                        # what the reader is handed, where that differs
```

Three fields earn their explanation:

**`slug` is not `title`.** The slug is the folder name and the string `SessionSound` stores in `UserDefaults`; the title is the supplier's name for the voice. Keeping them apart is what lets a voice be swapped for a better one without moving a file, touching Swift, or breaking anybody's saved setting.

**`say` exists because punctuation is a synthesis hint, not copy.** A bare one-word cue has no sentence shape to sit in and the model guesses at one — "In" came back anywhere between 0.25s and 2.12s across repeats, while "In." lands inside a tenth of itself every time. The full stop is a direction to the reader, so it must not reach the screen.

**`model` is named here rather than in code**, so trying a different one is an edit and a re-render. It is deliberately not `eleven_v3`: v3 is the expressive one, and expressive here means unrepeatable — the same "Breathe in" came back at 0.61s, 0.58s and 2.15s across three requests, and a cue that sometimes pauses in the middle is not a cue.

## Adding or swapping a voice

```bash
mise run voice:list        # ids and accents this account can render with
# edit crates/toolkit/voice/en.toml
mise run generate:voice    # renders every cue for every voice
mise run test:swift        # the drift guards
```

Nothing in Swift changes. `SessionVoice.all` is read from `voices.json`, the picker sorts on `variant` then `title`, and `SessionAudioPlayer` loads whatever stems the manifest lists.

Two things to check by ear and by number afterwards:

- **Speed.** Voices do not arrive at one pace, and the ceiling is fixed: alternate-nostril breathing's authored four seconds has to hold "Breathe in through your right nostril". A voice whose longest cue overruns that loses the nostril the exercise is named for, and `SpokenCueFitTests` says so.
- **The default.** Exactly one voice must carry `default = true`. The render refuses to start otherwise, rather than leaving the app to guess which voice somebody meets first.

`generate:voice` sits **outside** the `generate` chain, beside `check:diagrams` and for the same reason — it needs `ELEVENLABS_API_KEY` and macOS's `afconvert`, and a chain that fails in a headless environment teaches people to skip the chain.

## What the render does

`crates/toolkit/src/voice.rs`, one request per cue per voice:

1. **Validate every manifest first**, before a single request is spent — an unfilled voice id or a missing default is a first-second failure, not one discovered after the fifty-fifth clip is paid for.
2. **Ask for `pcm_24000`** — raw 16-bit PCM at the rate the cue tones are already synthesised at, so measuring where the speech starts needs no decode.
3. **Trim and normalise.** Raw clips are roughly twice their speech and are not level-matched: peaks ranged nearly two to one, and a "hold" landing twice as loud as a "breathe out" wakes somebody up rather than settling them. Everything is normalised to a fixed peak, with 30ms kept either side of the speech so a clip does not open on the attack of its first consonant.
4. **Encode to mono AAC** through `afconvert`, into `ios/Packages/OndCore/Sources/OndKit/Resources/Voice/<slug>/<cue>.m4a`. AAC rather than the WAV the tones use, because these resources ship to the watch too and a re-rendered WAV set is half a megabyte of binary churn per retune.
5. **Write `voices.json`** — what each voice says for each cue, and how long saying it takes.

The order is load-bearing. `voices.json` is deleted **before** the first clip is overwritten and written **after** the last one lands, because a run that dies halfway would otherwise leave new audio beside the durations of the old — and the fit rule reads those durations. A missing manifest is loud; a stale one says nothing.

Pruning runs after the renders, and removes anything the manifests no longer name: a dropped voice's folder, and a dropped cue's clip inside a folder that stayed.

## Which cue a phase gets

Several of the seeded catalogue's phases are shorter than the sentence describing them, so `Breath.spokenCue` picks one of three (`ios/Packages/OndCore/Sources/OndKit/VoiceClips.swift`):

|                                                   | when                                                                    |
| :------------------------------------------------ | :---------------------------------------------------------------------- |
| **full** — "Breathe in through your left nostril" | the phase runs longer than `sentenceFloor` (2s) _and_ the sentence fits |
| **short** — "In"                                  | the sentence does not fit, or the phase is two seconds or less          |
| **tone**                                          | not even the word fits; the phase keeps the tone it always had          |

Two rules inside that are worth knowing:

**It is measured against the slowest voice, not the current one.** "Breathe out" spans 0.57s to 1.48s across the eight, near enough three to one. Deciding on the slowest costs a quick voice some headroom it did not need, and buys a session that does not change shape when somebody changes voice.

**Fitting and having room for are not the same.** Wim Hof's 1.5s breath holds "Breathe in" with half a second to spare, and the result is a phase spent listening to a sentence rather than taking a breath. Under two seconds a phase is a beat, and one word is the whole of what a beat can carry.

It is also measured against the phase **as it will be breathed** rather than as it was authored — every duration is one a dial can move.

The sigh is the deliberate exception to the one-word rule. Its inhale, top-up and release are one connected instruction — "Breathe in", "And in", "And breathe out" — rendered as three clips with sentence punctuation supplied through `say`. Each clip still has to fit its own phase against the slowest voice; a dialled phase too short for its fragment keeps the tone rather than clipping a word.

## What stops the audio drifting from the words

The render is manual, key-gated and macOS-only, so forgetting it is the likely mistake rather than the unlikely one — and a forgotten render is invisible: the clips still play, still sound right, and say something the app stopped saying. Five tests cover it, none needing a key, a network or a simulator.

| Test                                                    | Catches                                                                                      |
| :------------------------------------------------------ | :------------------------------------------------------------------------------------------- |
| `a_manifest_is_ready_to_render` (Rust)                  | a typo, an unfilled id, two voices sharing a folder — before requests are spent              |
| `the_committed_clips_say_what_the_manifests_say` (Rust) | a cue reworded in TOML and never re-rendered                                                 |
| `nothing_ships_that_the_manifests_do_not_name` (Rust)   | an orphan: a dropped cue's audio still in the bundle                                         |
| `VoiceCoverageTests` (Swift)                            | a breath, register or voice with no clip; a clip whose text has drifted from `Breath.spoken` |
| `SpokenCueFitTests` (Swift)                             | a voice that overruns the phase it speaks into                                               |

The first three run in `mise run test:rs`, the last two in `mise run test:swift`. Together they mean a reworded cue fails the gate rather than shipping audio saying the old thing.

## Committing a render

**Sweep the whole of `Resources/Voice` — every add, every modify, every delete.**

The render is not incremental: trimming and normalisation run over the set, so adding one cue re-cuts every file. Staging only the clips that look new leaves a commit whose `voices.json` describes audio the commit does not contain, and no test catches it — they compare words to words, not bytes to bytes. This has happened, so verify with `shasum` before calling it done.

## Where a second language goes

A new language is a new TOML beside `en.toml`, with its own `cues` table and its own voices. Nothing in the render or the app is English-specific.

Two things follow when one is committed, and neither blocks anything above: `Breath.spoken` moves to a String Catalog in OndKit, and clips move to `Resources/Voice/<locale>.lproj/` so `Bundle` resolves the locale with no Swift logic. The `.lproj` move is not made pre-emptively because it requires `defaultLocalization` in `ios/Packages/OndCore/Package.swift`, which changes resource handling for the whole package — `catalogue.json` included.

One rule to set when it lands: **a locale with no clips falls back to tones, never to English speech.** A French app saying "Breathe in" is worse than a beep.
