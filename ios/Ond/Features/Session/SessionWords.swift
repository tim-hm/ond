import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What the live session says: the three slots under the orb and, inside a
/// retention, the button that ends it. Its own view because the words answer a
/// different question from the drawing above them — a phase's wording, not its
/// geometry — and because they run on a clock of their own.
struct SessionWords: View {
    let model: SessionModel

    @Environment(SessionSettings.self) private var settings

    /// The largest text these words are drawn at. The reserved slot heights
    /// are what keep phases crossfading in place, and an accessibility size
    /// would break them. The session header caps with them; everything else on
    /// the screen scales the whole way.
    static let mostGrowth = DynamicTypeSize.xxLarge

    /// Whether the words are the session's one spoken element. Under Just the
    /// visuals they are not and the guide carries the phase itself — except
    /// inside a retention or a pause, which only the words report. Asked once,
    /// by both, so the two cannot both answer or both stay silent.
    static func speak(for model: SessionModel, under guidance: SessionGuidance) -> Bool {
        guidance == .full || model.isInHold || model.status == .paused
    }

    /// One one-second tick for the lot: the count changes by the second, the
    /// aim turns on the second it passes, and the spoken value is the seconds
    /// left in the phase. Rebuilding this at display refresh once made
    /// VoiceOver stutter.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let moment = moment
            let spoken = spoken(at: moment)

            VStack(spacing: Theme.Spacing.loose) {
                SessionSlots(
                    action: action(at: moment),
                    qualifier: qualifier(at: moment),
                    count: count(at: moment)
                )
                .dynamicTypeSize(...Self.mostGrowth)
                // One element wearing two strings rather than a branch per
                // state: a branch gives the slots a second identity, and
                // SwiftUI then replaces them where they were to crossfade.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken.label)
                .accessibilityValue(spoken.value)
                .accessibilityHidden(!Self.speak(for: model, under: settings.guidance))

                if moment.held != nil {
                    release(aim: moment.aim)
                }
            }
        }
    }

    /// One instant of the session, sampled once. Everything the words say
    /// comes off this rather than a fresh read: the plan's clock and the
    /// retention's both go to the hardware, and two reads in one pass is how
    /// the printed count and the spoken value come to name different seconds.
    private struct Moment {
        let beat: SessionTimeline.Beat?
        let elapsed: Duration
        let isPaused: Bool
        /// The retention's own clock as the screen prints it, or nil where
        /// there is no retention.
        let held: String?
        let aim: String?
    }

    private var moment: Moment {
        let beat = model.describingBeat
        let elapsed = model.elapsed
        let isPaused = model.status == .paused

        guard model.isInHold else {
            return Moment(beat: beat, elapsed: elapsed, isPaused: isPaused, held: nil, aim: nil)
        }

        let held = model.holdElapsed
        return Moment(
            beat: beat,
            elapsed: elapsed,
            isPaused: isPaused,
            held: held.formatted(.time(pattern: .minuteSecond)),
            aim: beat?.target.map { aim(of: $0, after: held) }
        )
    }

    /// What a frozen session says in place of the cue and the count. Pause
    /// holds the plan where it stands rather than resetting it, and these two
    /// words are how the screen says so.
    private static let pausedAction = "Paused"
    private static let pausedCount = "held"

    /// The Action slot's word. Blank under Just the visuals, where the slot
    /// keeps its height and the orb carries the phase on its own — but a pause
    /// says so at every guidance level: it is the screen answering why nothing
    /// is moving, not a cue somebody asked to be spared.
    private func action(at moment: Moment) -> String {
        guard !moment.isPaused else { return Self.pausedAction }
        guard settings.guidance == .full else { return "" }

        return moment.beat?.instruction ?? ""
    }

    /// The Qualifier slot: what the body is doing that the cue cannot say. It
    /// takes the session's accent only where it names the side being breathed
    /// through — `Passage.Side`, never the wording of the line.
    private func qualifier(at moment: Moment) -> SessionSlots.Qualifier? {
        guard settings.guidance == .full, !moment.isPaused else { return nil }
        guard let beat = moment.beat, let line = beat.hint.line else { return nil }

        return SessionSlots.Qualifier(
            line: line,
            accent: beat.passage?.side == nil ? nil : model.accent
        )
    }

    /// The Count slot. A pause outranks everything, retentions included: the
    /// screen says `held` and gives the number back on resume. A running
    /// retention shows its own clock at every guidance level, since the orb is
    /// frozen and that number is what the button acts on. Elsewhere the
    /// phase's seconds are always supplied and the hold's crossfade shows them.
    private func count(at moment: Moment) -> SessionSlots.Count? {
        guard !moment.isPaused else {
            return SessionSlots.Count(text: Self.pausedCount, presence: 1)
        }
        if let held = moment.held {
            return SessionSlots.Count(text: held, presence: 1)
        }
        guard settings.guidance == .full, let beat = moment.beat else { return nil }

        return SessionSlots.Count(
            text: secondsRemaining(in: beat, at: moment.elapsed),
            presence: BreathGlyph.Pose.holdPresence(
                near: beat,
                in: model.timeline,
                at: moment.elapsed
            )
        )
    }

    /// What VoiceOver reads off the words. A paused session swaps both strings
    /// rather than relabelling one: left alone it would go on reading the
    /// frozen cue as an instruction, on a screen whose visible words say the
    /// opposite. A retention answers with its own clock and the aim after it,
    /// which is a `Text` of its own on screen but one phrase to the ear.
    private func spoken(at moment: Moment) -> (label: String, value: String) {
        guard !moment.isPaused else { return (Self.pausedAction, Self.pausedCount) }

        let label = spokenPhase(of: moment.beat)
        guard let held = moment.held else {
            return (label, secondsRemaining(in: moment.beat, at: moment.elapsed))
        }

        return (label, moment.aim.map { "\(held), \($0)" } ?? held)
    }

    /// What ends an open-ended hold, and what this round asked for. The button
    /// is the only thing that ends a retention, so it stays whatever the
    /// guidance level says.
    private func release(aim: String?) -> some View {
        VStack(spacing: Theme.Spacing.close) {
            if let aim {
                Text(aim)
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.tertiary)
                    // Spoken as part of the slots' value above, where it reads
                    // as one phrase with the count it qualifies.
                    .accessibilityHidden(true)
            }

            Button("I'm ready") {
                model.release()
            }
            .font(.headline)
            .padding(.horizontal, Theme.Spacing.loose)
            .padding(.vertical, Theme.Spacing.close)
            .background(.thinMaterial, in: Capsule())
            .disabled(model.status != .holding)
            .accessibilityHint("Ends the hold and takes the recovery breath")
        }
    }

    /// What this round asks for, in the calmest words the screen can put it in —
    /// and, once the time is behind them, an invitation to stop rather than a
    /// prompt to keep going.
    private func aim(of target: Duration, after held: Duration) -> String {
        let length = target.formatted(.time(pattern: .minuteSecond))
        return held >= target
            ? "Past \(length) — end whenever you like"
            : "Aim for \(length)"
    }
}
