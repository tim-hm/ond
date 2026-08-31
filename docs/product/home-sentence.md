# The Home sentence

Home holds three things: the breath at rest, one line of plain language, and the button. This document is the copy matrix behind that line — the cases, the exact strings, and the order the cases are tested in. The implementation is [`HomeStateLine.swift`](../../ios/Packages/OndCore/Sources/OndKit/Home/HomeStateLine.swift), and every string below is pinned by [`HomeStateLineTests.swift`](../../ios/Packages/OndCore/Tests/OndKitTests/Home/HomeStateLineTests.swift).

The line has one job: say what this week holds, and give the reader nothing to brace for. It is the emotional centre of the screen, which is why it is written here rather than improvised at the call site.

## The rules the copy is written under

**Celebrate consistency, never pressure.** The line reports. It does not ask, suggest, or compare this week with a better one. There is no target in it and no verb in the imperative.

**No line is ever a streak.** A streak is a number that can be lost, and a number that can be lost is a reason to open an app out of fear. The line never counts days in a row, and it never names what stopped.

**When there is nothing true to say, it says nothing.** The line is absent, not blank: the layout closes up and the button moves nearer the breath. Nothing yet is the case that does this, and it is a real option in the matrix rather than a fallback — broken week is a second, softer form of the same rule, saying nothing of its own.

**An early end is said as an early end.** The record distinguishes a session the timeline finished from one a person stopped, and the line volunteers that rather than rounding it up. It states the fact and stops there: `ended early`, with no clause after it. The app states the shape of the record and passes no verdict on it.

## The matrix

| Case                  | Condition                                                              | Line                                                     |
| :-------------------- | :--------------------------------------------------------------------- | :------------------------------------------------------- |
| Nothing yet           | No session has ever been recorded                                      | none — the layout closes up                              |
| Nothing this week     | Sessions exist, none of them in the current week                       | `Nothing this week yet.`                                 |
| First session         | The week's one session, with nothing recorded before it                | `Your first session is recorded.`                        |
| Returning after a gap | The week's one session, at least 14 whole days after the one before it | `Your first session back is recorded.`                   |
| First week            | The week holds the whole history, and holds more than one session      | `Three sessions in your first week.`                     |
| Normal week           | Anything else                                                          | `One session this week.` · `Three sessions this week.`   |
| Broken week           | A week whose practised days are not consecutive                        | none of its own — it reads as the normal week it also is |

Counts one to nine are spelled as words and capitalised, because each one opens a sentence; ten and above stay digits. `Foundation` spells the word, because a hand-written English table would not survive a localised build.

Whichever sentence wins, an early end is added to it rather than replacing it:

| Selected sentence | One early end                                                       | Two or more                                       |
| :---------------- | :------------------------------------------------------------------ | :------------------------------------------------ |
| A week's count    | `Four sessions this week. One you ended early.`                     | `Three sessions this week. Two you ended early.`  |
| A single session  | folded into the one sentence: `One session this week, ended early.` | not possible — one session cannot end early twice |

A week of one session takes the folded form because `One session this week. One you ended early` is two sentences about one thing.

## Broken week

**Definition.** A week that holds at least two practised days with at least one unpractised day between them. A week with one practised day cannot be broken: there is no interior gap to find. A week with no sessions at all is not broken either — it is the `Nothing this week yet.` case, which is tested first and takes the line before the question is asked. So the boundary is exact: an empty week is a different sentence, a one-day week is a normal week, and a broken week starts at two non-adjacent days.

**Decision: it says nothing of its own.** A broken week renders the ordinary weekly count, exactly as an unbroken week with the same number of sessions does.

The reasoning is the second rule. Any sentence that distinguishes a broken week from a whole one has to name the break, and naming the break is the app keeping score — a streak written in prose instead of digits. `Three sessions this week, and one quiet stretch` is the same message as a broken flame icon, delivered more politely. Nor is there a kind version of the fact: a person who practised on Monday and Thursday already knows what happened on Tuesday, and telling them buys nothing they can use.

Inverting it — praising the _unbroken_ week — was considered and rejected too. It makes the plain count into the consolation prize, so a gap still costs something. Under these two rules the honest outcome is that the app does not have an opinion about which days the sessions landed on, and the copy should not pretend otherwise.

This is a decision, not an omission, so it is tested: a gapped week asserts the plain count in `HomeStateLineTests`. Anyone who later adds a broken-week string will see that test fail and find this paragraph.

## Returning after a gap

**Definition.** The week's one session, when at least **14 whole days** separate it from the most recent session before it. The gap is measured between the two sessions' local calendar days, using the same calendar the week is counted in, so Home and Progress cannot disagree about a boundary.

**Why 14.** Fourteen days is the smallest gap that guarantees a whole calendar week passed with nothing in it, whatever weekdays the two sessions fell on. Thirteen does not: two sessions thirteen days apart can leave every calendar week touched. So the threshold is not a taste; it is the point at which "this week" stops being able to tell the story on its own. A skipped week is ordinary — a holiday, a cold, a bad fortnight at work — and an app that treats one of them as an absence is applying pressure.

**The copy.** `Your first session back is recorded.`

It deliberately mirrors `Your first session is recorded.`, because a return is a first session of a new stretch and deserves the same sentence. It says nothing about how long the gap was, congratulates nobody, and welcomes nobody back. A `Welcome back!` line is pressure wearing a friendly face: it tells the reader the app noticed they were gone, which makes the next gap something to be noticed for.

Its early-end form follows the first-session pattern: `Your first session back, ended early.`

**Boundary with first session.** A first session has nothing recorded before it, so no gap can be measured from it. The two cases are mutually exclusive by definition, not by ordering — a person cannot return before they have arrived.

**Scope.** The case applies only while the return is still the week's one session. Once a second session lands, the count is the truer summary and the return goes unsaid; the week is no longer a single act. Saying both would be two sentences about one thing, which is the same reason a one-session week folds its early end.

## Precedence

Seven cases share one sentence, so they collide. The order they are tested in:

1. **Nothing yet** — an empty history. There is no week to describe.
2. **Nothing this week** — an empty current week. Everything below needs a session inside the week.
3. **The week's one session** — its standing decides the sentence: first, returning, or ordinary.
4. **The week's count** — first week or this week, for two sessions or more.
5. **The early-end clause** — added to whichever sentence won.

The order runs from the emptiest fact to the fullest, and each step needs what the step above it ruled out. Only one step is a genuine contest.

**Returning beats the count.** `One session this week.` and `Your first session back is recorded.` are both true of the same record. The return wins because it carries the count as well — one session back is one session — while the count carries nothing about the return. It is strictly more informative at no cost in pressure.

**Early ending never loses.** It is a clause, never a case, so it survives every sentence above it. This is the one thing in the matrix that is a promise rather than a preference: the app said it would not round an abandoned session up, and a case that could swallow the clause would break that promise quietly.

**A broken week has no precedence** because it selects no sentence. It is a condition the code deliberately does not test for, described here so the next editor knows the absence is intended.

## Still open

- The line is a function of the session history alone. It knows nothing about the mood check, the occasion a session came from, or the time of day, and none of those has an argued case for entering it yet. The first one that does should be argued here before it is written.
- Fourteen days is defended above as the smallest principled threshold, not as a measured one. Nobody has watched a returning person read the line. If real usage says a fortnight is too long or too short, change the number here and in `returnGapDays` together — the code comment on the constant points back at this section rather than repeating it.
