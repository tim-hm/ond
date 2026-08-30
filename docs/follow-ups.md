# Follow-ups

Open items that came out of finished work. Each one is here because somebody deliberately did **not** do it at the time, and said why.

This is not a decision log — [README.md](README.md) explains why the repo has none. A decision that has been made goes next to the code it governs. This file holds only what is still open, and an item leaves it the moment it is done or dropped. If an entry has stopped being true, delete it.

Each entry says what is open, why it was left, and what closes it.

## Blocked on design

**The haptic pattern.** §4 of the visual refresh names the haptic pattern as the primary channel for a session with the screen off. No pattern is designed: not the per-phase signatures, not hold against rest, not phone against watch, not intensity. Screen-off mode does not ship without it. A phase can now carry a `haptic_pattern` key through the contract, the schema and the catalogue export, but nothing authors one and no client resolves one: an identifier can be shaped without the design, a pattern cannot. _Closes when design delivers the pattern._

**The board is unreachable for a new user.** `BoardCard` on Progress is the only door to leaderboards, and the spec hides the board until there is at least one session. So the feature is invisible to the people most likely to be looking for a reason to come back. One session opens it. _Closes when design decides whether a new user sees a board, an empty board, or nothing._

**The playful register ships half-styled.** `PlayfulBreathVisual` was ported onto the refreshed session layout unchanged, by decision. §12 of the spec says it either becomes a designed mode or it goes. _Closes when design picks one._

**Per-exercise cadence tables are not written.** A phase can carry an authored turn gap, haptic pattern and voice script, and every one of them is null in the seed, so every session still derives all three. Writing the tables is design work per exercise, and the turn gap, the tap and the spoken line are one deliverable rather than three. _Closes when design delivers a cadence per exercise._

## Decisions somebody has to look at

**The board ranks minutes, and the consent screen warns about over-practice.** Leaderboards rank streaks, minutes and comfortable pauses. Ranking minutes rewards practising longer, in an app whose safety terms caution against exactly that. Ranking days practised would carry the same social proof without the dose incentive. _Closes when design decides what the board ranks._

**Tab icons lost their selected chrome.** The spec asked for SF Symbols and the app now uses them. The custom set existed to draw an outline when selected; SwiftUI substitutes its own filled variants instead. Built the spec's way on purpose. _Closes when design has seen the result on a device and confirms it._

**History rows lost the cycle count.** The refreshed row is a dot, an exercise name and a right-aligned time. The count is gone from the screen and from what a screen reader hears. _Closes when design confirms the count is not wanted, or names where it goes._

**History pages by rows, not by days.** The spec says three days load with the screen. The code pages 50 rows, which is the server's own page size, and takes whole days so a day's total is never stated over part of it. Changing to a three-day page is a model change, not a view change. _Closes when the paging unit is decided._

## Spec conflicts — built the other way, deliberately

**Ink alphas.** §1 of the spec prints `Ink` alphas the palette cannot hold at AA. `Ink.secondary` and `Ink.tertiary` stay deeper than the spec's numbers. `ThemeColorTests` measures tertiary at 4.75:1, and the spec's own floor calls an alpha "a ceiling of quietness, not a licence to fail AA". Moving them to the printed values fails the test. _Closes when design restates the alphas or accepts the measured ones._

**"Show earlier sessions" is `Accent.brandText`, not `Breath.inhale`.** The spec asks for `inhale`. Its light value measures 4.01:1 against the ground, under the 4.5:1 floor for text this small. `brandText` is the token that already holds the app's blue for type. _Closes when design confirms the substitution._

## Code

**The watch counts holds with its own copy of the phone's logic.** Both derive the same count from the same clock, and only the phone's is tested. A change to one will not reach the other. _Closes when the derivation is shared._

**Choosing Sweeping on the phone does not reach the wrist.** `WatchSettings` carries no `breathVisual`, so the watch selects Sweeping from Reduce Motion alone rather than from the shared `drawn(underReduceMotion:)` resolver. Somebody who picks Sweeping on the phone still gets a scaling core on their wrist. _Closes when the setting reaches the watch._

**The watch's display size is written out four times.** The wrist sets its display face at 22pt in the session view, the root menu, the session summary and the consent screen. No token holds it, so the four can drift apart. _Closes when one token holds the wrist's display size._

**A prescription now keeps a phase's manner, and no test says so.** `Prescription.dialled` used to drop the manner and now carries it. Nothing changes today, because both seeded prescriptions target `extended-exhale`, which has no manner. The change is real but unobservable, so nothing will catch it when a prescription first targets an exercise that has one. _Closes when a test pins what a dialled prescription keeps._

**A day header can say "Today" after midnight.** Nothing re-renders Progress at the turn of the day, so an app left open on that screen keeps yesterday's header. _Closes when the view observes the day change._

**`CoachComposer` has no honest preview mode.** The free tier shows the real composer, disabled. A dishonest argument was removed rather than a preview mode added, because the composer belongs to another lane. _Closes when the composer states its own disabled case._

## Verification owed on hardware

The simulator answers these wrongly and confidently, so none of them is verified. Check the home screen's icon theme setting before judging the icon.

- The Live Activity, the lock screen, and all three Dynamic Island presentations. Specifically: whether the compact leading fits 26pt without clipping, whether the minimal presentation still reads, whether `0:04` fits the compact trailing, and whether the glass row plus the transport pair stays under the lock screen's roughly 160pt clip.
- Screen-off haptics.
- The app icon's tinted and clear renderings at 29pt.
- The 40mm watch layout at large text sizes.

Read the `.xcresult` bundle for any accessibility-audit failure. The console names no element.

## Repository

**GitHub Actions has been disabled since 2026-08-07.** `mise run check` on a developer's own machine is the whole of the evidence that anything works. [contributing.md](contributing.md) records what re-enabling it needs. _Closes when CI runs the gate again._
