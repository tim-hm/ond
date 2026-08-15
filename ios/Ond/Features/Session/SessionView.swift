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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// The seconds left before the session starts, or nil once it has. The
    /// count is presentation, not part of the session: the recorded duration
    /// starts when the first breath does.
    @State private var countdown: Int?

    /// Whether the optional reflection has interrupted the countdown. It is a
    /// branch rather than a gate: never tapping Check in leaves this false and
    /// the session begins when the first count reaches zero.
    @State private var isCheckingIn = false

    /// VoiceOver gets an untimed choice before the spoken countdown starts.
    /// Sighted use never reads this flag; after either accessible choice it
    /// stays true for the rest of this screen.
    @State private var hasConfirmedCountdown = false

    /// Whether the screen is still holding, waiting to be asked. False from the
    /// first frame for every entry but a notification's — see `Entry`.
    @State private var isWaiting: Bool

    /// Whether this screen's warning has been accepted, for the techniques that
    /// carry one. Per screen rather than read back off the store on purpose: an
    /// acceptance without the tick is recorded but silences nothing, so this
    /// flag is what lets it open exactly the session it was given for.
    @State private var hasAcceptedWarning = false

    /// Both halves of "how do you feel", carried from the screen that asks to
    /// the summary that asks again — see `MoodCheckModel`, which holds every
    /// rule about when an answer counts.
    @State private var mood = MoodCheckModel()

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
                    title: model.title,
                    reached: model.reachedStage,
                    mood: mood
                ) { dismiss() }
            } else if let gate {
                switch gate {
                case .invitation:
                    SessionInvitationView(technique: model.technique) {
                        isWaiting = false
                    } onDecline: {
                        dismiss()
                    }

                case let .warning(warning):
                    TechniqueWarningView(warning: warning) { silenced in
                        warnings.accept(warning, silenced: silenced)
                        hasAcceptedWarning = true
                    } onDeclined: {
                        dismiss()
                    }
                }
            } else if isCheckingIn {
                MoodCheckView(check: mood)
            } else if model.status == .ready {
                CountdownView(
                    count: countdown ?? 3,
                    register: register,
                    showsCheckIn: settings.asksHowYouFeel && !mood.isAsked,
                    waitsForStart: waitsForAccessibleStart,
                    onCheckIn: beginCheckIn,
                    onStart: beginAccessibleCountdown
                ) { dismiss() }
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
        .task(id: mayCountDown) { await runCountdown() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.dismiss()
            // The backstop for the departures a status never reports — a screen
            // swiped away before it began, or closed while still waiting to be
            // asked. Every ending that a running session *does* reach is the
            // monitor's own, because this closure does not run for a session that
            // finishes with the phone in a pocket.
            pulse.release()
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
        .onChange(of: mood.isAsked) { _, isAsked in
            guard isAsked, isCheckingIn else { return }
            countdown = nil
            hasConfirmedCountdown = true
            isCheckingIn = false
        }
        // A false start — ended by hand inside the first seconds — was never
        // recorded, so there is no summary to show; the screen just goes.
        .onChange(of: model.status) { _, status in
            if status == .finished, model.wasDiscarded {
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

    /// What still stands between this screen and its countdown, if anything.
    ///
    /// One computation for both the drawing and the starting. The `body` above
    /// switches on it and `mayCountDown` asks whether it is empty, so a gate added
    /// here cannot be drawn without also holding the count off — the failure
    /// the old pair of a chained `if` and a hand-written conjunction invited,
    /// which would have started a session underneath a screen still asking
    /// something.
    private enum Gate: Equatable {
        /// The screen opened without anybody asking for it — see `Entry`.
        case invitation
        /// The technique carries a caution nobody has accepted yet.
        case warning(SessionWarning)
    }

    /// The gates in the order they are answered. A technique's caution comes
    /// before anything asks how somebody feels about practising it.
    private var gate: Gate? {
        if isWaiting {
            return .invitation
        }

        guard !hasAcceptedWarning,
              let warning = model.warning,
              warnings.needsWarning(for: warning)
        else { return nil }
        return .warning(warning)
    }

    private var waitsForAccessibleStart: Bool {
        voiceOverEnabled && !hasConfirmedCountdown
    }

    private var mayCountDown: Bool {
        gate == nil && !isCheckingIn && !waitsForAccessibleStart
    }

    /// Opens the optional reflection only while the session is still waiting.
    /// Releasing the wrist here keeps a check-in with no time limit from holding
    /// a workout open; the fresh countdown arranges it again.
    private func beginCheckIn() {
        guard model.status == .ready,
              settings.asksHowYouFeel,
              !mood.isAsked
        else { return }

        isCheckingIn = true
        pulse.release()
    }

    /// VoiceOver's explicit alternative to Check in. Resolving the optional
    /// choice first removes its timed button before the spoken count begins.
    private func beginAccessibleCountdown() {
        if settings.asksHowYouFeel {
            mood.skipBefore()
        }
        hasConfirmedCountdown = true
    }

    /// Counts three seconds down and then starts the session. The guard makes
    /// a re-fired task (or a session already under way) a no-op rather than a
    /// second countdown over a running breath — and holds the count off entirely
    /// on a screen still waiting to be asked, or still showing its warning.
    private func runCountdown() async {
        guard mayCountDown, model.status == .ready, countdown == nil else { return }

        // Handed the session rather than told when to start and stop: the monitor
        // follows its status from here, which is what keeps the wrist in step with
        // a session that finishes in somebody's pocket. Arranged from this line
        // rather than from the first breath so the wrist has the countdown's three
        // seconds to wake, take a workout and find a reading.
        //
        // Here rather than in `onAppear` because this is the moment somebody said
        // yes: a screen opened by a tapped reminder and left alone borrows nobody's
        // sensor.
        if settings.showsWristPulse {
            pulse.follow(model)
        }

        for count in [3, 2, 1] {
            countdown = count
            let lead = count == 3 ? "\(register.settlingLine). \(register.countdownLine) " : ""
            AccessibilityNotification.Announcement("\(lead)\(count)").post()
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled || isCheckingIn {
                // Cleared on the way out, or a cancelled count leaves its last
                // digit on screen forever: the re-fired task's `countdown ==
                // nil` guard would read the leftover as a count still running.
                pulse.release()
                countdown = nil
                return
            }
        }

        guard !isCheckingIn else {
            pulse.release()
            countdown = nil
            return
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
