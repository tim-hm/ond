import OndKit
import OndStyle
import OndUI
import SwiftUI

struct WatchSessionPlayerView: View {
    let model: SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(WatchSettings.self) private var settings
    private static let countSize: CGFloat = 13
    private static let countStep = 1.0

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                VStack(spacing: Theme.Spacing.close) {
                    remainingTime
                    if model.isInHold {
                        hold
                    } else {
                        phase
                    }
                    controls
                }
            }
        } else {
            GeometryReader { proxy in
                VStack(spacing: Theme.Spacing.close) {
                    if model.isInHold {
                        hold
                    } else {
                        phase
                    }

                    visual
                    controls
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    /// Open-ended stages have no reliable remaining duration.
    @ViewBuilder
    private var remainingTime: some View {
        if !model.technique.hasOpenEndedStage {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("\(model.remaining.formatted(.time(pattern: .minuteSecond))) left")
                    // A text style, not a fixed size, so the one number
                    // on the face grows with the wrist's text setting.
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Ink.secondary)
            }
        }
    }

    private var visual: some View {
        let motion = AirOrbMotion(timeline: model.timeline)
        let sweeping = settings.breathVisual.drawn(underReduceMotion: reduceMotion) == .sweeping

        return GeometryReader { proxy in
            let room = max(0, min(proxy.size.width, proxy.size.height) - Theme.Spacing.close)
            let side = min(WatchAirOrb.designSide, room)

            TimelineView(.animation(
                minimumInterval: Theme.Motion.restfulFrameInterval,
                paused: model.status != .running && model.status != .holding
            )) { _ in
                let elapsed = model.elapsed
                let beat = model.timeline.beat(at: elapsed)

                WatchAirOrb(
                    frame: motion
                        .frame(at: elapsed, realElapsed: model.realElapsed, stationary: sweeping),
                    side: side
                )
                .overlay {
                    if sweeping {
                        PhaseArc(
                            fraction: beat?.fraction(at: elapsed) ?? 0,
                            tint: beat?.kind.isHold == true ? Theme.Breath.hold : model.accent,
                            lineWidth: 3
                        )
                        .frame(width: side, height: side)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// Keep one detail row reserved so hints and hold counts do not move the orb.
    private var phase: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let elapsed = model.elapsed
            let beat = model.timeline.beat(at: elapsed)
            let count = count(of: beat, at: elapsed)

            VStack(spacing: Theme.Spacing.tight) {
                Text(model.status == .paused ? "Paused" : beat?.instruction ?? "")
                    .displaySerif(size: 22)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: Theme.Spacing.close) {
                    if model.timeline.hintsAnyBeat {
                        Text(beat?.hint.glance ?? " ")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                    countLine(count)
                }
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
        HStack(spacing: Theme.Spacing.close) {
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

            if !dynamicTypeSize.isAccessibilitySize {
                remainingTime
            }

            control("stop.fill", label: "End") {
                model.end()
            }
        }
        .padding(.bottom, Theme.Spacing.standard)
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
