# Follow-ups

Open items that came out of finished work. Each one is here because somebody deliberately did **not** do it at the time, and said why.

This is not a decision log — [README.md](README.md) explains why the repo has none. A decision that has been made goes next to the code it governs. This file holds only what is still open, and an item leaves it the moment it is done or dropped. If an entry has stopped being true, delete it.

Each entry says what is open, why it was left, and what closes it.

## Blocked on design

**The wrist cannot follow the phone's haptic strength.** The cadence design asks the watch to run one notch quieter than the phone by default. watchOS has no amplitude control, so the only thing that can vary is pulse spacing, which the same design ratifies unchanged. The two tap weights carry the hold asymmetry the design calls load-bearing, so softening either destroys it. The watch also keeps its own settings and deliberately ignores a stored strength. _Closes when design says what a quieter wrist means without amplitude, or drops the ask._

**Choosing Sweeping on the phone does not reach the wrist.** `WatchSettings` carries no `breathVisual`, so the watch selects Sweeping from Reduce Motion alone rather than from the shared `drawn(underReduceMotion:)` resolver. Somebody who picks Sweeping on the phone still gets a scaling core on their wrist. The same channel would carry the haptic strength above. _Closes when the setting reaches the watch._

**The session arc takes no accent.** The cadence design lists the session arc among the three things a playful session colours. `SessionArc` strokes `Breath.inhale` and takes no accent at all, on phone and wrist. Making it accent-driven recolours every session on both devices, which is a refresh-scale change rather than a register one. _Closes when design confirms every session's arc should carry its accent._

**There is no days-practised board.** The cadence design asks the leaderboard to lead on days practised, on the sound reasoning that ranking minutes rewards practising longer in an app whose safety terms caution against exactly that. No such board exists: `streak` counts days in a row, not days turned up. The captions now lead with streaks, which is the closest honest thing. _Closes when design decides whether to build the measure it asked for._

## Decisions somebody has to look at

**The playful accent's light value fails AA at the number design printed.** The cadence design prints `#A8536A`. It measures 4.49:1 on the light ground, under the 4.5:1 floor for text. The shipped `#8F4C5E` measures 5.49:1 and is what the app uses. The design's own rule for light accents would break its own contrast floor. _Closes when design accepts the measured value or supplies one that clears AA._

**"Never how calm anybody got" is not true of this app.** The phrase appears in the design's proposed caption and appeared in the code. The Resting breathing board ranks the slowest resting breathing rate, which is a measured calm state rather than something somebody did. The captions leave the phrase out. _Closes when design either drops the claim or drops the board._

**A long hold is a fourth haptic element.** The design says the vocabulary is three elements, and that a hold is silent after its mark. It then puts a reminder tap every fifteen seconds inside a hold. The tap is built, because the pattern table names it. _Closes when the vocabulary and the table agree._

**A long hold's reminders stop at the length it aims for.** The Wim Hof retention is ended by hand, and the plan only knows the length the hold aims for, so the reminders stop there. The design does not say what should happen past the aim. _Closes when design says whether a retention keeps reminding._

**Bellows Breath can never speak its form cue.** The design says it speaks once, at cycle four. Cycle four speaks the short word, so the first form cue falls at cycle eight, and there the clip does not fit a one-second phase against the slowest voice. The exercise is silent throughout. _Closes when design accepts the silence or shortens the line._

**The design's Voice column is prose, not data.** Most printed lines name no clip that exists. Box breathing's hold-out is printed as `Rest` and the shipped clip says `Hold`; 4-7-8, pursed-lip and cooling print sentences nothing speaks. Only the sigh trio and the two silent rows are authorable today, and those are seeded. _Closes when design says which printed lines are meant to become clips._

## Code

**The watch counts holds with its own copy of the phone's logic.** Both derive the same count from the same clock, and only the phone's is tested. A change to one will not reach the other. _Closes when the derivation is shared._

**The watch's display size is written out four times.** The wrist sets its display face at 22pt in the session view, the root menu, the session summary and the consent screen. No token holds it, so the four can drift apart. _Closes when one token holds the wrist's display size._

**A prescription now keeps a phase's manner, and no test says so.** `Prescription.dialled` used to drop the manner and now carries it. Nothing changes today, because both seeded prescriptions target `extended-exhale`, which has no manner. The change is real but unobservable, so nothing will catch it when a prescription first targets an exercise that has one. _Closes when a test pins what a dialled prescription keeps._

**A day header can say "Today" after midnight.** Nothing re-renders Progress at the turn of the day, so an app left open on that screen keeps yesterday's header. _Closes when the view observes the day change._

**`CoachComposer` has no honest preview mode.** The free tier shows the real composer, disabled. A dishonest argument was removed rather than a preview mode added, because the composer belongs to another lane. _Closes when the composer states its own disabled case._

**The app target has no unit tests, and cannot have them.** `ios/Ond/` declares only a UI-testing bundle, so nothing in it can be reached by a Swift test, and `mise run check` never compiles that Swift at all. A screen reader regression in the history row went unnoticed for exactly this reason. Rules worth pinning have to move into `OndKit` one at a time. _Closes when the app target can be tested, or when the pattern of moving rules out is written down as the rule._

**The reserved `silent` cue is known only to Swift.** A phase whose `voice_script` is `silent` says nothing at any cycle. The database column checks length alone, and no Rust constant names the word, so a future seed could write `silent` meaning a clip and nothing would object. _Closes when the seed and the schema name the reservation too._

**A discreet wrist session cannot carry a register.** Neither `WristSessionHandoff` nor `DiscreetSessionModel` holds one, so that summary always uses the plain words. Nothing in the seed forbids a moment that is both playful and discreet, and one would speak playfully and then end plainly. _Closes when the register reaches the wrist's discreet path._

**The board tells a named subscriber it has no name.** `BoardCard`'s caption falls through to the opt-in line while the board is loading and while the network is down, so somebody who has already chosen a name reads "Off until you put a name to it." during every fetch. _Closes when the card states its loading and unreachable cases._

**A goal word on its own wash is not measured.** `ThemeColorTests` measures a text accent against the plain ground. The session's qualifier line sits on a wash of that same accent, where no accent clears AA. Pre-existing, and not introduced by the register work. _Closes when the wash has a measured floor, or the line moves off it._

## Verification owed on hardware

The simulator answers these wrongly and confidently, so none of them is verified. Check the home screen's icon theme setting before judging the icon.

- **The haptic onset marks**, with the screen dark and the phone face down. This is the whole point of the boundary marks and the simulator cannot answer it.
- The Live Activity, the lock screen, and all three Dynamic Island presentations. Specifically: whether the compact leading fits 26pt without clipping, whether the minimal presentation still reads, whether `0:04` fits the compact trailing, and whether the glass row plus the transport pair stays under the lock screen's roughly 160pt clip.
- The tab bar's selected state. SF Symbols replaced a custom set that drew an outline when selected, and design has accepted the substitution on the understanding that somebody confirms it on a device.
- The app icon's tinted and clear renderings at 29pt.
- The 40mm watch layout at large text sizes.

Read the `.xcresult` bundle for any accessibility-audit failure. The console names no element.
