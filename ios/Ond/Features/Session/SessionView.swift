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
    /// The wrist's heart rate, if this person asked for one and there is a wrist
    /// to ask. Read straight from the environment rather than passed in, because
    /// nothing between here and the composition root has any use for it.
    @Environment(PulseMonitor.self) private var pulse
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
                CountdownView(count: countdown, register: register) { dismiss() }
            } else {
                SessionPlayerView(model: model)
            }
        }
        .accentGround(model.accent)
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
            // The backstop for the departures the finish below never sees — a
            // screen swiped away mid-breath, or one closed while still waiting to
            // be asked. A wrist left sharing would hold a workout open for a
            // session that no longer exists.
            pulse.end()
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
        .onChange(of: model.status) { _, status in
            guard status == .finished else { return }

            // At the end of the breathing rather than at the end of the screen: a
            // summary may be read an hour later, and a wrist should not hold a
            // workout open for a session somebody has already finished.
            pulse.end()

            // A false start — ended by hand inside the first seconds — was never
            // recorded, so there is no summary to show; the screen just goes.
            if model.wasDiscarded {
                dismiss()
            }
        }
    }

    /// Which words and which drawing this session asked for, off the plan rather
    /// than off the beat on screen — the countdown and the warning both run
    /// before there is a beat, and all three have to agree from the first frame.
    private var register: CopyRegister {
        model.timeline.register
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

        // Asked for before the count rather than at the start, so the wrist has
        // those three seconds to wake, take a workout and find a first reading —
        // the badge is worth having from the first breath rather than the fifth.
        // Here rather than in `onAppear` because this is the moment somebody said
        // yes: a screen opened by a tapped reminder and left alone borrows nobody's
        // sensor.
        if settings.showsWristPulse {
            pulse.begin()
        }

        for count in [3, 2, 1] {
            countdown = count
            let lead = count == 3 ? "\(register.settlingLine). \(register.countdownLine) " : ""
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

    /// VoiceOver reads the screen once and would otherwise never mention that
    /// the phase changed — which is the only information the session carries.
    /// The nostril hint rides along, whatever the guidance level: wanting a
    /// quieter screen is not the same as hearing nothing.
    ///
    /// Silent when the session is about to speak this beat. The clip and the
    /// announcement are the same sentence from two engines a beat apart, and
    /// hearing "breathe in through your left nostril" twice over is worse than
    /// either alone — so the voice, which is the one that lands on the phase
    /// boundary, is the one that keeps it.
    ///
    /// Asked of the beat, not of the settings: the quick exercises fall back to
    /// a tone, and guarding on the setting silenced those too — the phases with
    /// least room to show anything were the only ones saying nothing at all.
    private func announceCurrentPhase() {
        guard let beat = model.currentBeat else { return }
        guard !settings.speaksPhases || beat.spokenCue == .tone else { return }
        AccessibilityNotification.Announcement(beat.spokenInstruction).post()
    }
}
