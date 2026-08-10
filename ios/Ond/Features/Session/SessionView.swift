import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session itself: one animated breath guide, the controls to interrupt it,
/// and the summary it hands over at the end.
struct SessionView: View {
    /// How the screen opens.
    ///
    /// A tap on Begin has already said yes, so the screen counts itself down and
    /// starts — which is every route through the app itself. A notification's
    /// tap has said only "show me this": the person was interrupted rather than
    /// settled, and a breath that begins because a reminder was tapped is the
    /// reminder practising rather than them.
    enum Entry {
        /// Straight into the countdown, because the way in was a Begin control.
        case beginning
        /// At rest, with the exercise named and a Begin control of its own.
        case waiting
    }

    @State private var model: SessionModel

    @Environment(SessionSettings.self) private var settings
    @Environment(TechniqueWarningStore.self) private var warnings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// The seconds left before the session starts, or nil once it has. The
    /// count is presentation, not part of the session: the recorded duration
    /// starts when the first breath does.
    @State private var countdown: Int?

    /// Whether the screen is still holding, waiting to be asked. False from the
    /// first frame for every entry but a notification's — see `Entry`.
    @State private var isWaiting: Bool

    /// Whether this screen's warning has been accepted, for the techniques that
    /// carry one. Per screen rather than read back off the store on purpose: an
    /// acceptance without the tick is recorded but silences nothing, so this
    /// flag is what lets it open exactly the session it was given for.
    @State private var hasAcceptedWarning = false

    /// The session's presence on the lock screen and in the Dynamic Island, held
    /// so that leaving the screen takes it down again.
    ///
    /// It keeps itself in step from here on: it observes the model directly
    /// rather than being pushed to, because the minutes it exists for are the
    /// ones where this view is not being drawn at all.
    @State private var presence: SessionActivity?

    init(model: SessionModel, entering entry: Entry = .beginning) {
        _model = State(wrappedValue: model)
        _isWaiting = State(wrappedValue: entry == .waiting)
    }

    var body: some View {
        ZStack {
            if model.status == .finished, let record = model.record, !model.wasDiscarded {
                SessionSummaryView(
                    record: record,
                    technique: model.technique,
                    reached: model.reachedStage
                ) { dismiss() }
            } else if isWaiting {
                SessionInvitationView(technique: model.technique) {
                    isWaiting = false
                } onDecline: {
                    dismiss()
                }
            } else if showsWarning {
                TechniqueWarningView(technique: model.technique) { silenced in
                    warnings.accept(model.technique, silenced: silenced)
                    hasAcceptedWarning = true
                } onDeclined: {
                    dismiss()
                }
            } else if let countdown {
                CountdownView(count: countdown) { dismiss() }
            } else {
                player
            }
        }
        .accentGround(model.technique.goal.accent)
        .statusBarHidden()
        .onAppear {
            // A guided breath is watched, not touched, so the screen would dim
            // three phases in. Restored on the way out — this is a system-wide
            // setting and leaving it on would outlive the session.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        // `.task` rather than `onAppear`, so dismissing mid-count cancels it
        // and the session is never started under a screen that has gone. Keyed
        // on the gate so that a screen which opened at rest — or on a warning —
        // counts down when it is finally clear to, with the same cancellation
        // it would have had.
        .task(id: mayBegin) { await runCountdown() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.dismiss()
            // The Activity ends itself when the session does, so this is the
            // backstop for the sessions that never reach that — a screen swiped
            // away mid-countdown, or closed while still waiting to be asked.
            presence?.end()
        }
        // A session follows the person out of the app as far as its cues can
        // reach them, and no further: sound reaches a pocket, so a session with
        // it keeps running; nothing else does, so a session without it stops and
        // says that it stopped. One rule, and the half of it about which cues
        // reach a pocket is written on `SessionCues.playsInBackground`.
        //
        // The notice is what makes the stop honest rather than merely quiet, and
        // only a departure that changed something is worth one — which is what
        // `pauseForScene()` answers. The return withdraws it either way, because
        // a departure the notice was never posted for is also one nothing here
        // remembers.
        //
        // `.background` and not `.inactive`, which iOS also sends for a
        // notification banner and a Control Centre pull — neither is a departure
        // and neither should cost the person a phase.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if model.pauseForScene() {
                    SessionPausedNotice.post()
                }

            case .active:
                SessionPausedNotice.withdraw()
                model.resumeIfSceneDriven()

            default: break
            }
        }
        .onChange(of: model.currentBeat?.id) { _, _ in announceCurrentPhase() }
        // A false start — ended by hand inside the first seconds — was never
        // recorded, so there is no summary to show; the screen just goes.
        .onChange(of: model.status) { _, status in
            if status == .finished, model.wasDiscarded {
                dismiss()
            }
        }
    }

    /// Whether the technique's own warning still stands between this screen and
    /// its countdown — see `TechniqueWarningView` for whose screens that is.
    private var showsWarning: Bool {
        !hasAcceptedWarning && warnings.needsWarning(for: model.technique)
    }

    /// Everything that has to be out of the way before the count can start:
    /// the invitation answered, the warning accepted.
    private var mayBegin: Bool {
        !isWaiting && !showsWarning
    }

    /// Counts three seconds down and then starts the session. The guard makes
    /// a re-fired task (or a session already under way) a no-op rather than a
    /// second countdown over a running breath — and holds the count off entirely
    /// on a screen still waiting to be asked, or still showing its warning.
    private func runCountdown() async {
        guard mayBegin, model.status == .ready, countdown == nil else { return }

        for count in [3, 2, 1] {
            countdown = count
            let lead = count == 3 ? "Get comfortable. Starting in " : ""
            AccessibilityNotification.Announcement("\(lead)\(count)").post()
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                // Cleared on the way out, or a cancelled count leaves its last
                // digit on screen forever: the re-fired task's `countdown ==
                // nil` guard would read the leftover as a count still running.
                countdown = nil
                return
            }
        }

        countdown = nil
        model.start()
        // After the start, not before: the Activity draws a phase, and until
        // the session is running there is no phase to draw.
        presence = SessionActivity.begin(for: model)
    }

    private var player: some View {
        VStack(spacing: Theme.Spacing.loose) {
            header

            Spacer()
            if model.isInHold {
                HoldView(model: model)
            } else {
                breathGuide
            }
            Spacer()

            controls
        }
        .padding(Theme.Spacing.loose)
        // Set once for the screen: everything under here is text on the accent
        // ground, where primary is the only ink that clears AA, and the buttons
        // carry their own tint over it.
        .foregroundStyle(Theme.Ink.primary)
    }

    /// Everything that changes at a phase boundary rather than at display
    /// refresh, so it sits outside the animation timeline below and is rebuilt
    /// when `currentBeat` or `status` changes instead of sixty times a second.
    private var header: some View {
        VStack(spacing: Theme.Spacing.tight) {
            Text(model.technique.name)
                .font(.headline)
            // Primary ink, quieter only by size: on the accent ground the
            // secondary step measures 3.26:1 and this line is `.subheadline`,
            // so there is no tone left to spend on hierarchy here.
            Text(position)
                .font(.subheadline)
        }
    }

    /// "Cycle 3 of 8", or "Round 2 of 3 · cycle 12 of 30" once there are rounds
    /// to keep track of. The round is the number that matters in a staged
    /// protocol, and the cycle is meaningless without it.
    private var position: String {
        let cycle = "Cycle \(model.currentCycle) of \(model.cyclesInCurrentStage)"
        guard model.timeline.rounds > 1 else { return cycle }
        return "Round \(model.currentRound) of \(model.timeline.rounds) · \(cycle.lowercased())"
    }

    /// Two timelines, because only the orb moves at display refresh.
    ///
    /// It redraws every frame and reads elapsed time back off the session's
    /// clock, so the visual follows the same timeline the cues do rather than an
    /// animation running alongside it — paused when the session is.
    ///
    /// The words tick once a second, which is as often as the count changes. On
    /// the frame timeline their combined accessibility element was rebuilt a
    /// hundred times a second, and an accessibility tree invalidated that often
    /// is what makes VoiceOver stutter over the phase instead of reading it.
    ///
    /// The phase itself comes off `describingBeat` — the same answer the header
    /// above is written from — rather than off the sampled clock, so the word
    /// changes on the boundary rather than at the next tick. At four seconds a
    /// phase that lag was a rounding error; at one it is most of the phase, and
    /// bellows breathing would spend half of every breath telling somebody to do
    /// the opposite of what the orb is doing.
    private var breathGuide: some View {
        VStack(spacing: Theme.Spacing.loose) {
            TimelineView(.animation(paused: model.status != .running)) { _ in
                let elapsed = model.elapsed
                breathVisual(beat: model.timeline.beat(at: elapsed), elapsed: elapsed)
            }

            // Under Just the visuals the words leave the screen, not the
            // accessibility tree — the orb above then carries them, so a
            // VoiceOver user can always re-read the phase, not only catch
            // its announcement.
            if settings.guidance == .full {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let elapsed = model.elapsed
                    let beat = model.describingBeat

                    VStack(spacing: Theme.Spacing.close) {
                        Text(beat?.kind.instruction ?? "")
                            .font(.title2.weight(.medium))
                        // Which nostril, and alternate-nostril breathing cannot
                        // be done without it — so it takes the one ink the
                        // accent ground leaves readable. Drawn in the accent it
                        // sits on it measured 2.93:1; the weight is what marks
                        // it out now that the colour cannot.
                        if let hint = beat?.passage?.hint {
                            Text(hint)
                                .font(.subheadline.weight(.semibold))
                        }
                        if let beat, !beat.isFastRhythm {
                            Text(secondsRemaining(in: beat, at: elapsed))
                                .font(.system(.largeTitle, design: .rounded).weight(.light))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Ink.secondary)
                        }
                    }
                    .speaksPhase(beat, at: elapsed)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.loose) {
            Button {
                if model.status == .paused {
                    model.resume()
                } else {
                    model.pause()
                }
            } label: {
                transportLabel(
                    model.status == .paused ? "Resume" : "Pause",
                    systemImage: model.status == .paused ? "play.fill" : "pause.fill"
                )
            }
            .accessibilityLabel(model.status == .paused ? "Resume" : "Pause")

            // The pause control's twin, told apart by glyph alone. Stop rather
            // than an X: the pair reads as transport controls, and an X beside
            // them says "close this screen", which is not what ending a
            // session does — it hands over a summary.
            Button {
                model.end()
            } label: {
                transportLabel("End", systemImage: "stop.fill")
                    // The quiet ink the text button wore, kept on the glyph:
                    // a destructive control should read a step back from the
                    // pause beside it, or a reach for one is a mis-tap away
                    // from ending the session. The wrist's twin agrees.
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .accessibilityLabel("End")
            .accessibilityHint("Ends the session")
        }
        .padding(.bottom, Theme.Spacing.standard)
    }

    /// One transport control's face. The pair are twins told apart by glyph
    /// alone, so the chrome that makes them twins is written once.
    private func transportLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.title2)
            .frame(width: 64, height: 64)
            .background(.thinMaterial, in: Circle())
    }

    /// The session's one moving picture, with its accessibility role decided
    /// by guidance: under full the text block beside it speaks for the phase
    /// and the guide stays decorative; under Just the visuals the guide is the
    /// only phase display there is, so it carries the label itself.
    @ViewBuilder
    private func breathVisual(beat: SessionTimeline.Beat?, elapsed: Duration) -> some View {
        let visual = BreathVisual(
            beat: beat,
            elapsed: elapsed,
            progress: model.progress(at: elapsed),
            accent: model.technique.goal.accent
        )

        if settings.guidance == .full {
            visual.accessibilityHidden(true)
        } else {
            visual.speaksPhase(beat, at: elapsed)
        }
    }

    /// VoiceOver reads the screen once and would otherwise never mention that
    /// the phase changed — which is the only information the session carries.
    /// The nostril hint rides along, whatever the guidance level: wanting a
    /// quieter screen is not the same as hearing nothing.
    private func announceCurrentPhase() {
        guard let beat = model.currentBeat else { return }
        AccessibilityNotification.Announcement(beat.spokenInstruction).post()
    }
}

private extension View {
    /// Makes the receiver the session's one spoken element: the phase, and how
    /// long is left in it.
    ///
    /// Whichever of the two carries the phase wears this — the words under full
    /// guidance, the orb under Just the visuals — so the same screen is read the
    /// same way at either level, and the two cannot drift apart.
    ///
    /// Written out rather than combined from the labels on screen, because the
    /// seconds are still owed on a fast rhythm that does not print them: the
    /// wrist's rule, which took the digits off the screen and left them in
    /// VoiceOver.
    func speaksPhase(_ beat: SessionTimeline.Beat?, at elapsed: Duration) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(beat?.spokenInstruction ?? "")
            .accessibilityValue(secondsRemaining(in: beat, at: elapsed))
    }
}

/// Whole seconds left in the phase, counting down and never showing zero — the
/// last second of a phase is still a second of it.
private func secondsRemaining(in beat: SessionTimeline.Beat?, at elapsed: Duration) -> String {
    guard let beat else { return "" }
    return "\(beat.secondsRemaining(at: elapsed))"
}
