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
        ZStack {
            visual

            if model.isInHold {
                hold
            } else {
                phase
            }

            header
            controls
        }
    }

    /// The remaining time, as quiet chrome at the top of the face — the number
    /// the session ring used to carry. Only where the plan knows its own end:
    /// an open-ended stage makes "left" a number nobody stands behind.
    @ViewBuilder
    private var header: some View {
        if !model.technique.hasOpenEndedStage {
            VStack {
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
                Spacer()
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
    /// Rested under Reduce Motion — `BreathRing` fills an arc, at
    /// `Theme.Motion.restfulFrameInterval` — the whole branch, unlike the phone.
    private var visual: some View {
        TimelineView(.animation(
            minimumInterval: reduceMotion ? Theme.Motion.restfulFrameInterval : nil,
            paused: model.status != .running
        )) { _ in
            let elapsed = model.elapsed

            BreathRing(
                beat: model.timeline.beat(at: elapsed),
                elapsed: elapsed,
                timeline: model.timeline,
                accent: model.technique.goal.accent
            )
        }
        // The phase text below is the accessible description of all this.
        .accessibilityHidden(true)
    }

    /// The phase word in the display face, the seconds under it, and where it
    /// matters the passage the breath travels through.
    ///
    /// Ticking once a second, which is as often as the count changes — the
    /// word itself only changes at a boundary.
    private var phase: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let elapsed = model.elapsed
            let beat = model.timeline.beat(at: elapsed)

            VStack(spacing: Theme.Spacing.tight) {
                Text(model.status == .paused ? "Paused" : beat?.instruction ?? "")
                    .displaySerif(size: 26)

                // The count keeps still on a fast rhythm, where a digit
                // flicking every second is noise rather than a measure —
                // the phone's rule, kept so two wrists and a phone agree.
                if model.status != .paused, let beat, !beat.isFastRhythm {
                    Text("\(beat.secondsRemaining(at: elapsed))")
                        .font(.footnote)
                        .monospacedDigit()
                }

                // The glance form, held to one line: a 40mm case is 162pt
                // wide, and a wrapped hint would push the disc above it on
                // one beat of the cycle — the jump `hintsAnyBeat` reserves
                // the line to prevent.
                if model.timeline.hintsAnyBeat {
                    Text(beat?.hint.glance ?? " ")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            // Primary ink with a soft shadow, because these words sit on the
            // disc: the accent behind them is mid-luminance, where secondary
            // grey disappears into the colour it is read against.
            .foregroundStyle(Theme.Ink.primary)
            .shadow(color: .black.opacity(0.4), radius: 3)
            .accessibilityElement()
            // The full hint, not the glance form drawn above: what this screen
            // lacks is width, which a spoken label does not. Paused swaps the
            // whole label — a frozen cue read as an instruction tells a
            // VoiceOver user to keep breathing a session that is stopped.
            .accessibilityLabel(
                model.status == .paused ? "Paused" : beat.map(Self.spokenPhase) ?? ""
            )
            .accessibilityValue(
                model.status == .paused
                    ? "" : beat.map { "\($0.secondsRemaining(at: elapsed))" } ?? ""
            )
        }
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
                    // Same contrast rule as the phase word: this count sits on
                    // the frozen disc, not on the black ground.
                    .foregroundStyle(Theme.Ink.primary)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .accessibilityLabel(model.currentBeat?.spokenInstruction ?? "")
                    .accessibilityValue(spokenHoldValue)

                if let target = model.currentBeat?.target {
                    // Only the number: the wrist has no room for the sentence
                    // the phone writes around it.
                    Text("aim \(target.formatted(.time(pattern: .minuteSecond)))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Ink.primary)
                        .shadow(color: .black.opacity(0.4), radius: 3)
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
        VStack {
            Spacer()
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
            ? "Past \(length) — end whenever you like"
            : "Aim for \(length)"
        return "\(count), \(aim)"
    }
}
