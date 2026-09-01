import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session itself: one animated breath guide, the controls to interrupt it,
/// and the summary it hands over at the end.
struct SessionView: View {
    /// How the screen opens. A tap on Begin has already said yes, so the
    /// screen counts itself down and starts. A notification's tap has said
    /// only "show me this": a breath that begins because a reminder was
    /// tapped is the reminder practising rather than the person.
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
    /// Where an answered check-in goes. Read from the environment for the
    /// monitor's reason above: nothing between here and the root uses it.
    @Environment(MoodRecorder.self) private var moodRecorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// The seconds left before the session starts, or nil once it has. The
    /// count is presentation, not part of the session: the recorded duration
    /// starts when the first breath does.
    @State private var countdown: Int?

    /// Which run of the countdown owns the digit on screen and the wrist. A run
    /// cancelled part way wakes to put both back, and this stops it doing that
    /// to the run that replaced it.
    @State private var countdownRun = 0

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

    /// The session's presence on the lock screen and in the Dynamic Island,
    /// held so that leaving the screen takes it down again. It observes the
    /// model directly rather than being pushed to: the minutes it exists for
    /// are the ones where this view is not being drawn at all.
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
                    exercise: model.technique.name,
                    register: register,
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
            } else if model.status == .ready {
                CountdownView(
                    count: countdown ?? 3,
                    register: register,
                    preparation: model.technique.preparation,
                    showsCheckIn: settings.asksHowYouFeel && !mood.wasDeclinedBefore,
                    mood: mood.before,
                    waitsForStart: waitsForAccessibleStart,
                    onMood: answerCheckIn,
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
        // Asked only where somebody is asked how they feel at all: the answer
        // costs a round trip to the health daemon, and the check is the only
        // thing it decides.
        .task {
            guard settings.asksHowYouFeel else { return }
            await mood.expectPrompt(moodRecorder.writeMayPrompt())
        }
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
        // A session follows the person out only as far as its cues reach:
        // sound reaches a pocket, so it keeps running; without it the session
        // stops and says so — `SessionCues.playsInBackground` holds the other
        // half. `.background`, not `.inactive`, which iOS also sends for a
        // banner or a Control Centre pull — neither should cost a phase.
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

    /// Which words and which drawing this session asked for, off the plan rather
    /// than off the beat on screen — the countdown and the warning both run
    /// before there is a beat, and all three have to agree from the first frame.
    private var register: CopyRegister {
        model.timeline.register
    }

    /// What still stands between this screen and its countdown, if anything.
    /// One computation for both the drawing and the starting: `body` switches
    /// on it and `mayCountDown` asks whether it is empty, so a gate added here
    /// cannot be drawn without also holding the count off — the failure a
    /// chained `if` beside a hand-written conjunction invited.
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
        gate == nil && !mood.holdsCountdown && !waitsForAccessibleStart
    }

    /// Takes the optional check-in without leaving the countdown. Nothing is
    /// released here: where the write can raise a sheet, dropping
    /// `mayCountDown` cancels the running count and that run gives the wrist
    /// back on its way out. Where it cannot, the count is never touched.
    private func answerCheckIn(_ answer: Mood) {
        Task { await mood.answerBefore(answer) { await moodRecorder.note($0) } }
    }

    /// VoiceOver's explicit start, which holds the count until it is asked for.
    /// Resolving the check-in here takes an untouched scale off the screen
    /// before the spoken count begins; an answered one is left where it is.
    private func beginAccessibleCountdown() {
        if settings.asksHowYouFeel {
            mood.skipBefore()
        }
        hasConfirmedCountdown = true
    }

    /// Counts three seconds down and then starts the session. The guard makes a
    /// task fired over a running breath a no-op rather than a second countdown
    /// — and holds the count off entirely on a screen still waiting to be
    /// asked, still showing its warning, or writing the one check-in that can
    /// raise Health's own sheet.
    private func runCountdown() async {
        guard mayCountDown, model.status == .ready else { return }

        countdownRun += 1
        let run = countdownRun

        // Handed the session rather than told when to start and stop: the
        // monitor follows its status, keeping the wrist in step with a session
        // that finishes in a pocket, and the countdown's three seconds let it
        // wake and find a reading. Here, not `onAppear`, because this is the
        // moment somebody said yes — a tapped reminder borrows nobody's sensor.
        pulse.follow(model, wanted: settings.showsWristPulse)

        for count in [3, 2, 1] {
            countdown = count
            // The preparation is deliberately not announced here: a sentence
            // spoken at three is cut off by the announcement at two.
            // `CountdownView` leaves it navigable instead.
            let lead = count == 3 ? "\(register.settlingLine). \(register.countdownLine) " : ""
            AccessibilityNotification.Announcement("\(lead)\(count)").post()
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled || mood.holdsCountdown {
                abandon(run)
                return
            }
        }

        guard !mood.holdsCountdown else {
            abandon(run)
            return
        }

        countdown = nil
        model.start()
        // After the start, not before: the Activity draws a phase, and until
        // the session is running there is no phase to draw.
        presence = SessionActivity.begin(for: model)
    }

    /// Puts back what a countdown that will not finish had taken. Silent where
    /// a later run already owns them, which is the ordinary case: the run a
    /// check-in cancelled wakes after the one that replaced it has begun.
    private func abandon(_ run: Int) {
        guard run == countdownRun else { return }
        pulse.release()
        countdown = nil
    }

    /// VoiceOver reads the screen once and would otherwise never hear that the
    /// phase changed — the only information the session carries. Every
    /// boundary, unconditionally: the cues are tones and taps, so nothing else
    /// is saying the phase and there is no second voice to talk over.
    private func announceCurrentPhase() {
        guard let beat = model.currentBeat else { return }
        AccessibilityNotification.Announcement(beat.spokenInstruction).post()
    }
}
