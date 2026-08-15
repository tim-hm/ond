import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session on the wrist: one breathing shape filling the face, and as close
/// to nothing else as the session allows.
///
/// Shaped after Mindfulness rather than after the phone. What a person needs
/// mid-breath is the shape moving and the tap on their wrist; a countdown they
/// have to focus on to read is the opposite of the thing being practised. So the
/// digits are gone from the screen — but not from VoiceOver, which has no shape
/// to watch and would otherwise lose the only measure of the phase there is.
///
/// Two further differences from the phone, both deliberate. There is no
/// countdown to the start — a wrist session begins from an explicit tap and the
/// person is already composed. And leaving the app does **not** pause: an
/// extended runtime session keeps the cues firing with the wrist down, which is
/// the posture most of these techniques are done in.
struct SessionView: View {
    @State private var model: SessionModel
    @State private var runtime = ExtendedRuntime()

    /// Whether the pause and end buttons are on screen. Hidden by default: they
    /// are needed twice a session at most, and the small Controls affordance is
    /// enough to make them discoverable without keeping the whole bar present.
    @State private var controlsShown = false
    /// Bumped by every reveal, and the identity of the auto-hide task — a fresh
    /// tap therefore restarts the countdown rather than racing the last one.
    @State private var reveals = 0

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called once a finished session has been read and acknowledged, which is
    /// where the wrist's recordings get their chance to reach the server. Here
    /// rather than on the way out of the catalogue, so the drain cannot start
    /// its RPC in the same instant the extended runtime session does.
    private let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// How long the controls stay up before getting out of the way again.
    private static let controlsLinger = Duration.seconds(4)

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
        .wristGround(model.technique.goal.accent)
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
        .task(id: ControlsLinger(reveals: reveals, isNavigated: isNavigated)) {
            // Nothing to count down where the controls are staying up anyway,
            // and letting it run would leave `controlsShown` reading false under
            // a control bar plainly on screen.
            guard reveals > 0, !isNavigated else { return }
            try? await Task.sleep(for: Self.controlsLinger)
            // A paused session keeps its controls: hiding them would leave the
            // only way to resume behind a tap nobody knows to make.
            guard !Task.isCancelled, model.status == .running else { return }
            withAnimation { controlsShown = false }
        }
    }

    private var player: some View {
        ZStack {
            visual

            if model.isInHold {
                hold
            } else {
                phase
            }

            if controlsAreUp {
                controls
                    .transition(.opacity)
            } else {
                showControls
                    .transition(.opacity)
            }
        }
        // The whole face, so a tap anywhere brings the controls back — there is
        // no target to find on a screen that is deliberately almost empty.
        .contentShape(Rectangle())
        .onTapGesture {
            reveals += 1
            withAnimation { controlsShown = true }
        }
    }

    /// Whether the full controls are in the view tree.
    ///
    /// A screen being navigated rather than touched keeps them up for the whole
    /// session. Other sessions retain a visible Controls affordance when the bar
    /// moves out of the way, in addition to the whole-face tap shortcut.
    ///
    private var controlsAreUp: Bool {
        controlsShown || isNavigated
    }

    /// Whether this screen is being stepped through rather than touched.
    ///
    /// The two assistive technologies SwiftUI reports, named rather than keeping
    /// the controls in the tree behind `allowsHitTesting(false)` — the shape
    /// that would cover every one of them, including the two it does not report.
    /// Whether an accessibility activation still reaches a button through that
    /// modifier is a device question, and the failure if it does not is a Pause
    /// that can be found and not pressed. Worth revisiting on hardware.
    private var isNavigated: Bool {
        voiceOverEnabled || switchControlEnabled
    }

    /// What the auto-hide countdown belongs to: the reveal that started it, and
    /// whether anything was holding the controls up while it ran.
    ///
    /// The reveal count alone was enough until the controls learned to stay up.
    /// A tap made with VoiceOver on starts a countdown that bails, and VoiceOver
    /// turned off later would leave the bar sitting over the breath for the rest
    /// of the session with nothing left to take it down — so the technologies
    /// are half the identity, and switching one off re-arms the count.
    private struct ControlsLinger: Equatable {
        let reveals: Int
        let isNavigated: Bool
    }

    /// What VoiceOver is told when the breath changes.
    ///
    /// The phase element below updates its label, but VoiceOver reads a screen
    /// once: a label changing under an element nobody is focused on is never
    /// spoken. Without this the wrist carries the phase only through haptics —
    /// so turning the taps off left the session silent to VoiceOver from the
    /// first breath to the last.
    ///
    /// The phone suppresses its announcement where the voice engine is about to
    /// say the same sentence. There is nothing to suppress against here: the
    /// wrist plays no clips, which is why `WatchSettings` carries haptics and
    /// nothing else.
    private func announceCurrentPhase() {
        guard let beat = model.currentBeat else { return }
        AccessibilityNotification.Announcement(spokenAnnouncement(for: beat)).post()
    }

    private func spokenAnnouncement(for beat: SessionTimeline.Beat) -> String {
        guard let target = beat.target else { return beat.spokenInstruction }
        let length = target.formatted(.time(pattern: .minuteSecond))
        return "\(beat.spokenInstruction). Aim for \(length)."
    }

    /// `TimelineView(.animation)` redraws every frame and reads the elapsed time
    /// back off the session's clock, so the visual follows the same timeline the
    /// taps do rather than an animation running alongside it. Paused when the
    /// session is, which stops the redraws as well as the breath.
    ///
    /// Rested under Reduce Motion, which is where `BreathRing` draws a filling
    /// arc instead of a scaling disc — see `Theme.Motion.restfulFrameInterval`.
    /// The setting is the whole of that branch here, unlike the phone, which
    /// also offers the arc as a choice.
    private var visual: some View {
        TimelineView(.animation(
            minimumInterval: reduceMotion ? Theme.Motion.restfulFrameInterval : nil,
            paused: model.status != .running
        )) { _ in
            let elapsed = model.elapsed

            BreathRing(
                beat: model.timeline.beat(at: elapsed),
                elapsed: elapsed,
                progress: model.progress(at: elapsed),
                accent: model.technique.goal.accent
            )
        }
        // The phase text below is the accessible description of all this.
        .accessibilityHidden(true)
    }

    /// The phase and, where it matters, the passage it travels through.
    ///
    /// Ticking once a second rather than once a phase: the word only changes at
    /// a boundary, but the seconds remaining ride on this element's accessibility
    /// value, and those left the visual layer without leaving VoiceOver.
    private var phase: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let elapsed = model.elapsed
            let beat = model.timeline.beat(at: elapsed)

            VStack(spacing: 0) {
                Text(beat?.instruction ?? "")
                    .font(.caption2)

                // The glance form, and held to one line. A 40mm case is 162pt
                // wide and this sits on the disc, inset further — "Through a
                // curled tongue" is more ink than there is room for, and a hint
                // that wrapped would push the disc above it on one beat of the
                // cycle, which is the jump `hintsAnyBeat` reserves the line to
                // prevent.
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
            // lacks is width, which a spoken label does not.
            .accessibilityLabel(beat.map(Self.spokenPhase) ?? "")
            .accessibilityValue(beat.map { "\($0.secondsRemaining(at: elapsed))" } ?? "")
        }
    }

    /// The cue and what the line adds, joined as the phone joins them in
    /// `View+SpeaksPhase`, so two devices read one beat alike.
    private static func spokenPhase(of beat: SessionTimeline.Beat) -> String {
        guard let addition = beat.hint.spokenAddition else { return beat.spokenInstruction }
        return "\(beat.spokenInstruction), \(addition)"
    }

    /// The retention. Nothing counts down here, because nothing knows how long
    /// this is: the timer counts up, and the button is the only thing that ends
    /// it. Both stay on screen through a hold whatever the controls are doing —
    /// this button is the only way out of a retention, and the count is the only
    /// feedback a frozen shape can give.
    ///
    /// The round's suggested length rides under the count, as it does on the
    /// phone: a number to aim for, never one to beat.
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

    /// Two small glass discs at the foot of the screen.
    ///
    /// Sized rather than left to `.bordered`, which stretches a toolbar-width
    /// button across the face and buries the shape underneath it. These sit over
    /// the breath, so they are the smallest thing a thumb can reliably hit and
    /// no larger.
    private var controls: some View {
        VStack {
            Spacer()
            HStack(spacing: Theme.Spacing.standard) {
                control(
                    model.status == .paused ? "play.fill" : "pause.fill",
                    label: model.status == .paused ? "Resume" : "Pause",
                    tint: Theme.Ink.primary
                ) {
                    if model.status == .paused {
                        model.resume()
                        // Straight back out of the way: somebody who has just
                        // resumed is watching the shape again.
                        withAnimation { controlsShown = false }
                    } else {
                        model.pause()
                    }
                }

                control("stop.fill", label: "End", role: .destructive, tint: .red) {
                    model.end()
                }
            }
            .padding(.bottom, Theme.Spacing.close)
        }
    }

    /// The small, persistent route back to Pause and End after they move out of
    /// the way. The whole-face tap remains a convenience, but this names the
    /// action and gives it a target somebody can find without already knowing
    /// the gesture.
    private var showControls: some View {
        VStack {
            Spacer()
            Button {
                reveals += 1
                withAnimation { controlsShown = true }
            } label: {
                Label("Controls", systemImage: "ellipsis")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Ink.primary)
                    .padding(.horizontal, Theme.Spacing.close)
                    .frame(minHeight: 34)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(
                minWidth: Theme.Metrics.minimumTapTarget,
                minHeight: Theme.Metrics.minimumTapTarget
            )
            .contentShape(.rect)
            .accessibilityLabel("Show controls")
            .padding(.bottom, Theme.Spacing.close)
        }
    }

    private func control(
        _ symbol: String,
        label: String,
        role: ButtonRole? = nil,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(tint)
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
