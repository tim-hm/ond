import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session on the wrist: one breathing shape filling the face, and as
/// close to nothing else as the session allows — the phase word, a small
/// count, the remaining time. Two deliberate differences from the phone: no
/// countdown, since a wrist session begins from an explicit tap; and leaving
/// the app does not pause — extended runtime keeps the cues firing wrist down.
struct SessionView: View {
    @State private var model: SessionModel
    @State private var runtime = ExtendedRuntime()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called once a finished session has been read and acknowledged, which is
    /// where the wrist's recordings get their chance to reach the server. Here
    /// rather than on the way out of the catalogue, so the drain cannot start
    /// its RPC in the same instant the extended runtime session does.
    private let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// The two lines under the orb, at §7's own sizes. The display cut
    /// shimmers small, which is what holds the word at 22 rather than lower.
    private static let phaseWordSize: CGFloat = 22
    private static let countSize: CGFloat = 13

    /// How long the count's presence takes to travel — the second it is
    /// sampled on, so the tween covers the gap between samples.
    private static let countStep = 1.0

    init(model: SessionModel, onFinished: @escaping () -> Void) {
        _model = State(wrappedValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            if model.status == .finished, let record = model.record, !model.wasDiscarded {
                SessionSummaryView(
                    record: record,
                    technique: model.technique,
                    reached: model.reachedStage
                ) {
                    onFinished()
                    dismiss()
                }
            } else {
                player
            }
        }
        .wristGround(ground)
        .navigationBarBackButtonHidden()
        // No title. The bar it would sit in is the tallest thing competing with
        // the breath for this screen, and the technique was named on the page
        // the person tapped to get here.
        .task {
            runtime.start()
            model.start()
        }
        .onDisappear {
            runtime.invalidate()
            model.dismiss()
        }
        .onChange(of: model.status) { _, status in
            guard status == .finished else { return }
            // The budget goes back the moment the breathing ends, not when the
            // screen does — a summary being read needs no runtime session.
            runtime.invalidate()
            // A false start — ended by hand inside the first seconds — was never
            // recorded, so there is no summary to show; the screen just goes.
            if model.wasDiscarded {
                dismiss()
            }
        }
        .onChange(of: model.currentBeat?.id) { _, _ in announceCurrentPhase() }
    }

    /// Black air for the live breath, the goal's wash for the summary. Black
    /// through the same modifier rather than a special case: black's gradient
    /// at the wash's strength is still black, so one line gives the player
    /// its deep ground and the summary its accent.
    private var ground: Color {
        model.status == .finished ? model.technique.goal.accent : .black
    }

    /// Pause and End are always on screen: two small discs at the foot are
    /// quieter than any affordance standing in for them — a capsule naming a
    /// menu is louder on a screen whose point is near-emptiness, and costs a
    /// tap and a guess to reach the two actions behind it.
    private var player: some View {
        VStack(spacing: 0) {
            header
            visual

            if model.isInHold {
                hold
            } else {
                phase
            }

            controls
        }
    }

    /// The remaining time, as quiet chrome at the top of the face — the number
    /// the session ring used to carry. Only where the plan knows its own end:
    /// an open-ended stage makes "left" a number nobody stands behind.
    @ViewBuilder
    private var header: some View {
        if !model.technique.hasOpenEndedStage {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("\(model.remaining.formatted(.time(pattern: .minuteSecond))) left")
                    // A text style, not a fixed size, so the one number
                    // on the face grows with the wrist's text setting.
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(1.1)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Ink.secondary)
            }
        }
    }

    /// What VoiceOver is told when the breath changes. The phase element
    /// updates its label, but a label changing under an element nobody is
    /// focused on is never spoken — turning the taps off left the session
    /// silent to VoiceOver. Unlike the phone there is nothing to suppress
    /// against: the wrist plays no clips.
    private func announceCurrentPhase() {
        guard let beat = model.currentBeat else { return }
        AccessibilityNotification.Announcement(spokenAnnouncement(for: beat)).post()
    }

    private func spokenAnnouncement(for beat: SessionTimeline.Beat) -> String {
        guard let target = beat.target else { return beat.spokenInstruction }
        let length = target.formatted(.time(pattern: .minuteSecond))
        return "\(beat.spokenInstruction). Aim for \(length)."
    }

    /// `TimelineView(.animation)` reads the elapsed time back off the
    /// session's clock every frame, so the visual follows the taps' timeline
    /// rather than an animation beside it; pausing stops the redraws too.
    /// Rested under Reduce Motion — `BreathRing` parks the breath and sweeps a
    /// ring, at `Theme.Motion.restfulFrameInterval` rather than every frame.
    private var visual: some View {
        // The face does not resize, so the fit is read once per layout rather
        // than inside the frame timeline, where it would cost a layout pass a
        // frame for an answer that cannot change.
        GeometryReader { proxy in
            let room = min(proxy.size.width, proxy.size.height)
            let side = max(BreathRing.leastSide, min(BreathRing.designSide, room))

            TimelineView(.animation(
                minimumInterval: reduceMotion ? Theme.Motion.restfulFrameInterval : nil,
                paused: model.status != .running
            )) { _ in
                let elapsed = model.elapsed

                BreathRing(
                    beat: model.timeline.beat(at: elapsed),
                    elapsed: elapsed,
                    timeline: model.timeline,
                    accent: model.technique.goal.accent,
                    side: side
                )
            }
        }
        // The phase text below is the accessible description of all this.
        .accessibilityHidden(true)
    }

    /// The phase word in the display face, the passage where it matters, and
    /// the seconds under both — below the orb, because a shape that scales
    /// cannot hold a line of unpredictable length. Ticking once a second,
    /// which is as often as the count changes; the word itself only changes
    /// at a boundary.
    private var phase: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let elapsed = model.elapsed
            let beat = model.timeline.beat(at: elapsed)
            let count = count(of: beat, at: elapsed)

            VStack(spacing: Theme.Spacing.tight) {
                Text(model.status == .paused ? "Paused" : beat?.instruction ?? "")
                    .displaySerif(size: Self.phaseWordSize)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // The glance form, held to one line: a 40mm case is 162pt
                // wide, and a wrapped hint would push the count under it on
                // one beat of the cycle — the jump `hintsAnyBeat` reserves
                // the line to prevent.
                if model.timeline.hintsAnyBeat {
                    Text(beat?.hint.glance ?? " ")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Theme.Ink.secondary)
                }

                countLine(count)
            }
            .foregroundStyle(Theme.Ink.primary)
            .accessibilityElement()
            // The full hint, not the glance form drawn above: what this screen
            // lacks is width, which a spoken label does not. Paused swaps the
            // whole label — a frozen cue read as an instruction tells a
            // VoiceOver user to keep breathing a session that is stopped.
            .accessibilityLabel(
                model.status == .paused ? "Paused" : beat.map(Self.spokenPhase) ?? ""
            )
            // The seconds on every phase, not only the ones the count is
            // drawn on: the fade is a way of keeping the screen still, and
            // VoiceOver has no such problem.
            .accessibilityValue(count?.text ?? "")
        }
    }

    /// A count and how present it is, 0...1 — the phone's `SessionSlots.Count`
    /// at wrist size. Presence rather than a flag: the count fades across a
    /// hold's boundary instead of appearing at it.
    private struct Count {
        let text: String
        let presence: Double
    }

    /// What the count says, and how much of it is on screen. It renders only
    /// during holds, which is what the presence carries: away from one the
    /// number is supplied and drawn at nothing, so the line keeps its room and
    /// the word above it never moves. A pause outranks the phase.
    private func count(of beat: SessionTimeline.Beat?, at elapsed: Duration) -> Count? {
        guard model.status != .paused else { return Count(text: "held", presence: 1) }
        guard let beat else { return nil }

        return Count(
            text: "\(beat.secondsRemaining(at: elapsed))",
            presence: BreathGlyph.Pose.holdPresence(
                near: beat,
                in: model.timeline,
                at: elapsed
            )
        )
    }

    /// The count's own line. Sampled a second at a time with the words and
    /// moved linearly between samples, as the phone moves it: the fade it
    /// rides is linear too, so the tween lands on it.
    private func countLine(_ count: Count?) -> some View {
        let presence = count?.presence ?? 0

        return Text(count?.text ?? " ")
            .displayNumeral(size: Self.countSize, design: .monospaced)
            .foregroundStyle(Theme.Ink.secondary)
            .opacity(presence)
            .animation(.linear(duration: Self.countStep), value: presence)
    }

    /// The cue and what the line adds, joined as the phone joins them in
    /// `View+SpeaksPhase`, so two devices read one beat alike.
    private static func spokenPhase(of beat: SessionTimeline.Beat) -> String {
        guard let addition = beat.hint.spokenAddition else { return beat.spokenInstruction }
        return "\(beat.spokenInstruction), \(addition)"
    }

    /// The retention. Nothing counts down, because nothing knows how long
    /// this is: the timer counts up and the button is the only way out, so
    /// both stay on screen whatever the controls are doing — the count is the
    /// only feedback a frozen shape can give. The round's suggested length
    /// rides under the count: a number to aim for, never one to beat.
    private var hold: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: Theme.Spacing.close) {
                Text(model.holdElapsed.formatted(.time(pattern: .minuteSecond)))
                    .font(.system(.title3, design: .rounded).weight(.light))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Ink.primary)
                    .accessibilityLabel(model.currentBeat?.spokenInstruction ?? "")
                    .accessibilityValue(spokenHoldValue)

                if let target = model.currentBeat?.target {
                    // Only the number: the wrist has no room for the sentence
                    // the phone writes around it.
                    Text("aim \(target.formatted(.time(pattern: .minuteSecond)))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Ink.secondary)
                        .accessibilityHidden(true)
                }

                Button("I'm ready") {
                    model.release()
                }
                .disabled(model.status != .holding)
                .accessibilityHint("Ends the hold and takes the recovery breath")
            }
        }
    }

    /// Two small glass discs at the foot. Sized rather than `.bordered`,
    /// which stretches a toolbar-width button across the face and buries the
    /// shape: the smallest thing a thumb can reliably hit. Twins told apart
    /// by glyph alone, as on the phone, and End carries no destructive role —
    /// ending a session destroys nothing; it hands over a summary.
    private var controls: some View {
        HStack(spacing: Theme.Spacing.standard) {
            control(
                model.status == .paused ? "play.fill" : "pause.fill",
                label: model.status == .paused ? "Resume" : "Pause"
            ) {
                if model.status == .paused {
                    model.resume()
                } else {
                    model.pause()
                }
            }

            control("stop.fill", label: "End") {
                model.end()
            }
        }
        .padding(.bottom, Theme.Spacing.close)
    }

    private func control(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Theme.Ink.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .frame(width: Theme.Metrics.minimumTapTarget, height: Theme.Metrics.minimumTapTarget)
        .contentShape(.rect)
        .accessibilityLabel(label)
    }

    /// The elapsed hold and its target as one spoken value. The target remains
    /// advice rather than a deadline, including once the count has passed it.
    private var spokenHoldValue: String {
        let count = model.holdElapsed.formatted(.time(pattern: .minuteSecond))
        guard let target = model.currentBeat?.target else { return count }

        let length = target.formatted(.time(pattern: .minuteSecond))
        let aim = model.holdElapsed >= target
            ? "Past \(length). End it when you want."
            : "Aim for \(length)"
        return "\(count), \(aim)"
    }
}
