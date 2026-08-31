# The session summary and the mood check

Every recorded session ends here. This document is the design behind that screen — what it says, which cases it has to answer, the exact strings, and what the mood check asks. The implementation is [`SessionSummaryView.swift`](../../ios/Ond/Features/Session/SessionSummaryView.swift) on the phone and [its wrist counterpart](../../ios/OndWatch/Features/Session/SessionSummaryView.swift); the strings are [`SessionSummaryLines.swift`](../../ios/Packages/OndCore/Sources/OndKit/Session/SessionSummaryLines.swift), pinned by [`SessionSummaryLinesTests.swift`](../../ios/Packages/OndCore/Tests/OndKitTests/Session/SessionSummaryLinesTests.swift). The mood check's own rules are [`MoodCheckModel.swift`](../../ios/Packages/OndCore/Sources/OndKit/Health/MoodCheckModel.swift).

The screen has one job: confirm the session counted, say what it was, and offer one way out. It is written here rather than improvised at the call site for the reason Home's line is — it is the last thing the app says about a practice, and the last thing said is the thing remembered.

## The screen is the session with the breathing removed

The summary keeps the session's ground, the field behind it, and the three slots the phase words stood in. Only the orb goes; the figures take its place. Nothing about the room changes when the breathing stops, so the screen reads as the end of the session rather than as a new one. The field holds still: the breathing has stopped, and a screen somebody sits and reads has nothing left to move for.

This is why the summary does not sit on the accent wash the countdown and the invitation sit on. Those screens are the way in, and the app's colour is still on them. The session is the one room darker than the app, and it holds until Done.

| Element  | Type                            | Reserved height |
| :------- | :------------------------------ | :-------------- |
| Headline | Newsreader Light 42pt           | 50pt            |
| Note     | 17pt, `Ink.secondary`, one line | 26pt            |
| Mark     | 15pt, `Ink.secondary`           | 22pt            |

The three heights are the live session's own. They are reserved for the same reason: the mark arrives a moment after the screen does, because the rung is only known once the session has been counted, and a line that arrived into no space would push everything under it down the screen while somebody was reading it.

The mood row below the figures is **not** a reserved slot, and the difference is the point. It changes height only when somebody taps it, and movement that answers a tap is the screen responding rather than the screen moving on its own.

## The rules the copy is written under

**Celebrate what happened, never grade it.** The headline says the session happened. It does not measure it, compare it with a better one, or rate the person who did it.

**An early end is said as an early end.** The record distinguishes a session the timeline finished from one a person stopped, and the note volunteers it. It states the fact and stops there, with no clause after it. The app states the shape of the record and passes no verdict on it.

**A zero is not a measurement.** A figure with nothing in it is not shown. `0 cycles` is true and says nothing the time does not already say, and three figures reading zero turn a screen that refuses to score into a scorecard of failure.

**One way out, always live.** Done is the screen's one action. No question on the screen gates it, and no answer is required to leave.

## The matrix

| Case        | Condition             | Headline            | Note                            |
| :---------- | :-------------------- | :------------------ | :------------------------------ |
| Completed   | The timeline ran out  | `Nicely done.`      | `You finished box breathing.`   |
| Ended early | The person stopped it | `That's a session.` | `You ended this session early.` |

Two headlines, not one. A single neutral headline for both would be the strictest reading of "never grade", but it would also take the warmth off the ordinary case to avoid praising the rare one. Two are honest because they describe two different records, not two different people.

`That's a session.` was chosen over the repo's earlier `Every breath counts`, which is a claim about worth rather than a statement of the record, and over `Nicely done.` for both, which rounds an abandoned session up. It answers the one doubt somebody who stopped early has — whether it counted — and answers it with the fact rather than with reassurance.

**The exercise is named only when the session ran to its end.** The note holds one line so the figures below it cannot move, and an early end has to spend that line on the ending. The exercise is on the record either way, and Progress names it there.

It is the **exercise's** name, never the occasion's. A session started from `When you can't get a satisfying breath` is titled by that occasion everywhere else, but an occasion title is a sentence: it would be cut short in one line, and it reads as the wrong noun inside this one.

### The playful register

A session started from `With your child` speaks `CopyRegister.playful` throughout, and the summary is the last thing it says. It keeps the register rather than dropping back to the standard words at the end.

| Case        | Headline              | Note                                     |
| :---------- | :-------------------- | :--------------------------------------- |
| Completed   | `You did it.`         | `You breathed extended exhale together.` |
| Ended early | `That was breathing.` | `You stopped this one early.`            |

The four lines are the plain four said to a small child, or to an adult sitting with one. They answer the same two questions, under the same two rules: `You did it.` states the record without measuring it, and `That was breathing.` answers the doubt an early end leaves — the playful reading of `That's a session.`

`together` is the register's one added word, and only the finished note carries it. The playful register is reachable from one occasion, which is a breath shared with a child by definition. The early note spends its line on the ending, exactly as the plain one does.

Nothing else about the screen changes. The figures, the mark, the mood check and the reserved heights are the same, and the colour is the session's own — `Accent.play`, which the whole session already wears.

### The mark

A session that crosses a rung says so, once, in the mark slot: `PracticeStage.arrival`'s existing sentence. This is where a first-ever session is answered — `That was your first session.` — so the headline needs no first-session case of its own. A session that crosses no rung leaves the slot empty, and the slot keeps its height.

A first session that also ended early gets both lines, and both are true. The mark never displaces the note.

### The figures

Three figures under the slots, in the treatment Progress uses for its own three: the value at 22pt semibold over a 12pt label.

| Figure  | Value             | Shown                              |
| :------ | :---------------- | :--------------------------------- |
| Cycles  | `cyclesCompleted` | when at least one cycle finished   |
| Time    | `m:ss`            | always                             |
| Breaths | `breathCount`     | when at least one breath was taken |

The middle label is `time`, not `minutes`: a session of forty seconds under a label saying minutes is a small lie, and it is exactly the session most likely to be read closely.

### A very short session

A session ended by hand inside ten seconds is a false start and never reaches this screen at all — the rule is `SessionRecord.isFalseStart`, and it exists so a journal is not made of mistaps. Above that threshold every session reaches the summary, however short.

A short one therefore renders `That's a session.`, the early-end note, and the figures that have something in them — often the time alone. That is the whole design for the case: no apology, no encouragement, and no third headline.

## The mood check

Two questions around one session, both optional, and neither of them a measurement.

**Before.** Drawn on the countdown itself, under the numeral. It asks `How do you feel right now?` The count keeps running behind it: the check is an offer, not a step, and a session begun in a hurry is never delayed by one. Ignoring it is how it is skipped, which is why there is nothing there to decline.

Answering does interrupt the count, for one reason only. The first mood written on an install opens Health's own authorization sheet, and a session that started behind that sheet would be breathing where nobody could see it. The count is held for exactly as long as the write takes — see `MoodCheckModel.answerBefore` and `SessionView.isAnsweringBefore` — and then **starts again from three** rather than resuming where it stopped. That is deliberate: a sheet can stand open for as long as somebody reads it, and coming back to `1` is no settling beat at all. Where the write returns at once, the count is never interrupted and never restarts.

**After.** Inline on the summary, under the figures. It asks `How do you feel now?` The summary is the one moment of a session with attention to spare, so a fourth full screen before Done would ask more than the answer is worth.

### The scale

Five points, drawn as the numerals `1` to `5` with only the two ends named — `Bad` on the left, `Great` on the right. Five words will not fit across a phone, and the two that matter are the two that say which way the row runs. At an accessibility text size the points stack and each says its own word instead.

Every point keeps that word behind its numeral. It is what VoiceOver reads, so a listener hears `Okay` rather than `3`, and it is what the summary says back — the pair is words, never a pair of numbers, because two numbers with a gap between them read as a score.

An odd count is the point of five: the middle is `Okay`, so somebody can report that nothing changed without picking a side. The five map onto Health's own -1...1 pleasantness axis in equal steps, which is the whole of what a State of Mind sample carries.

Both carry the same caption, `MoodCheckModel.caption`: `Context, not a score.` It stands before the answer and stays after it, because a pair of moods across a session is the one thing on this screen that invites reading a difference, and saying what the answer is for is cheaper than correcting a reading later.

The caption cannot say the answer is _used_ for anything. A mood is written to Apple Health on the phone it was tapped on and reaches nothing else — no field on the wire, no column, and not the coach. `HealthSettingsSection.swift` states that as a promise: `önd never sees them.` A caption that offered the answer to a coach would contradict the screen that asked for it.

**What the pair says back.** `Not good before · Good now` when both halves were answered, the later word alone when the way in was skipped. The rule is `MoodCheckModel.note`, and it states the two words without grading the distance between them.

### When it is skipped

| Condition                               | What happens                                                                                        |
| :-------------------------------------- | :-------------------------------------------------------------------------------------------------- |
| `asksHowYouFeel` is off                 | Neither question is asked and the row is absent — no placeholder, no note that nothing was recorded |
| The session was a false start           | There is no summary, so there is nothing to ask                                                     |
| The way in was ignored or never offered | The summary still asks; a single reading is still the person's own record                           |
| The answer is already given             | The question is replaced by the sentence, in place                                                  |
| A short session                         | It is still asked                                                                                   |

The last row is a decision, not an oversight. A threshold under which a person is not asked how they feel would need a number nobody can defend, and the app does not get to decide whose reading is worth keeping.

A session with no mood recorded says nothing about the absence. It is the same rule Home's line is written under: when there is nothing true to say, say nothing.

## The wrist

The same design at wrist scale, on the watch's own ground: the headline in Newsreader at 22pt, the note and the mark in the platform's caption styles, the figures, Done.

**The wrist reserves no slot heights.** The phone reserves them because its screen is fixed and a late line would push the figures under a reader's eye. The watch scrolls, so a line arriving extends the list instead — and holding three empty slots on a 40mm screen would spend most of it on air.

**The wrist has no mood check.** It has never asked the before half, and asking only the after half on the smaller screen would make the pair a phone feature that occasionally appears on a wrist. The wrist records the session; the phone asks how it felt.

## Still open

- The pulse curve under the figures is drawn only when a watch shared readings through the session. It is the one element here that is a chart, and nobody has argued whether a chart belongs on this screen at all.
- Nothing on the summary names the occasion a session came from, though the record carries one. A session started from `Awake at three` and one started from the exercise list read identically here.
- The headline is a function of `completed` alone. It knows nothing about the mood answers, the rung, or the time of day, and none of those has an argued case for entering it yet.
