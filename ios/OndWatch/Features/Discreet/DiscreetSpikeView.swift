#if DEBUG
    import Foundation
    import HealthKit
    import Observation
    import OndKit
    import os
    import SwiftUI
    import WatchKit

    /// The instrument discreet mode has to be built on top of, and nothing that
    /// ships: `#if DEBUG` keeps it out of every release build, and the row that
    /// reaches it is behind the same fence.
    ///
    /// The cadence runs under an `HKWorkoutSession` rather than the shipping
    /// `ExtendedRuntime`'s `WKExtendedRuntimeSession`, because a workout is the
    /// runtime discreet mode is heading for: it is the only kind the phone can
    /// launch remotely (`startWatchApp` requires one), the only kind that
    /// samples heart rate continuously, and it has no duration ceiling — which
    /// dissolves the thirty-minute question this spike originally existed to
    /// measure. What is still unknowable off a wrist, and what the watch
    /// simulator will answer confidently and wrongly — exactly as the phone
    /// simulator reported a healthy locked-screen session that did not exist on
    /// the device:
    ///
    /// 1. **Do haptics still arrive after a long silence?** The cadence is
    ///    deliberately sparse, up to thirteen minutes between bursts, and a
    ///    session that stays alive while doing nothing at all is a different
    ///    proposition from one accompanying continuous cueing.
    /// 2. **Does the system actually let the workout run unattended?** No
    ///    ceiling on paper is not the same as no interference on a wrist; the
    ///    state log records what happened and when.
    ///
    /// The log separates the two, which is the whole reason it exists. Each entry
    /// is written by the app *deciding* to tap; whether anything was felt is
    /// something only the person wearing it can say. A burst that appears here and
    /// was not felt means haptics are being withheld; a burst that never appears
    /// means the runtime went away, and the reason it went away is logged beside
    /// it.
    ///
    /// It owns its `HKWorkoutSession` directly rather than driving the
    /// shipping `WorkoutRuntime`, deliberately: that type documents having no
    /// state a view can react to, and this instrument is nothing but a visible
    /// log — bending a shipping design to serve a temporary instrument is how
    /// instruments become permanent. The cost is stated plainly: `begin()`
    /// below is a copy of `WorkoutRuntime.begin()`, and a change to how the
    /// shipping runtime starts must be mirrored here or the spike measures a
    /// runtime that no longer ships.
    @MainActor
    @Observable
    final class DiscreetSpike: NSObject {
        /// One thing that happened, and when — the elapsed time being the only
        /// clock that matters here, since the question is about intervals.
        struct Entry: Identifiable {
            let id: Int
            let elapsed: Duration
            let what: String
        }

        private(set) var log: [Entry] = []
        private(set) var isRunning = false

        private nonisolated static let logger = Logger(category: "discreet-spike")

        private let health = HKHealthStore()
        private var session: HKWorkoutSession?
        private var cadence: Task<Void, Never>?
        /// The workout start in flight, held so `end()` can cancel a budget
        /// still being asked for — the authorization sheet can outlast the
        /// run that wanted it.
        private var beginning: Task<Void, Never>?
        private var started: ContinuousClock.Instant?
        /// Held so `end()` can silence a purr mid-phase; the run task alone
        /// holding it would leave a hand-stop unable to reach the controller.
        private var cues: (any SessionCueing)?

        /// How far into the run the wrist is, or zero before it starts.
        var elapsed: Duration {
            started.map { ContinuousClock.now - $0 } ?? .zero
        }

        /// Runs the real cadence over `technique`, cued through the same
        /// controller a full-screen session uses so the taps under test are the
        /// taps that would ship.
        ///
        /// - Parameters:
        ///   - technique: what a burst is six breaths of.
        ///   - cues: the wrist's cue controller, which honours the haptics
        ///     switch — a run with haptics off proves nothing, and the log will
        ///     still say the bursts fired.
        func start(technique: Technique, cues: some SessionCueing) {
            guard !isRunning else { return }

            let started = ContinuousClock.now
            isRunning = true
            log = []
            self.started = started
            note("spike started")

            self.cues = cues
            // Concurrent, exactly as the shipping screen starts WorkoutRuntime
            // beside the model: awaited ahead of the cadence, a first-run
            // authorization sheet would backdate burst one's deadlines and
            // machine-gun its taps — distorting the very timing under test.
            beginning = Task { await begin() }
            cadence = Task { await run(technique: technique, cues: cues, from: started) }
        }

        /// Stops early, by hand. Not the thing being measured — a run that
        /// answers the questions ends by itself.
        func end() {
            beginning?.cancel()
            beginning = nil
            cadence?.cancel()
            cadence = nil
            cues?.stop()
            cues = nil
            release()
        }

        /// Asks for the workout runtime. A refusal is a finding, not a failure:
        /// the cadence runs regardless, and the log says which runtime — if
        /// any — was underneath it when the bursts landed or went missing.
        private func begin() async {
            guard HKHealthStore.isHealthDataAvailable() else {
                note("no health store — cadence runs with no runtime")
                return
            }

            // Starting a workout session requires the share grant for the
            // workout type even though this one never saves anything.
            try? await health.requestAuthorization(toShare: [.workoutType()], read: [])
            // End can land while the sheet is up; a session created past that
            // point would have no owner left to end it.
            guard !Task.isCancelled else { return }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .mindAndBody

            do {
                let session = try HKWorkoutSession(
                    healthStore: health,
                    configuration: configuration
                )
                session.delegate = self
                self.session = session
                session.startActivity(with: Date())
                note("workout session asked to start")
            } catch {
                // `String(describing:)` rather than `localizedDescription`:
                // the full error is more use on a debug instrument, and the
                // note is already logged public.
                note("workout session refused: \(String(describing: error))")
            }
        }

        private func run(
            technique: Technique,
            cues: some SessionCueing,
            from started: ContinuousClock.Instant
        ) async {
            let burst = DiscreetCadence.burst(of: technique)
            let clock = ContinuousClock()

            for (index, burstStart) in DiscreetCadence.burstStarts.enumerated() {
                // Sleeping to an absolute deadline rather than for a gap's
                // length: a wake-up the system delayed by a minute must not
                // push every later burst by a minute too, or a late schedule
                // would read as a missing one.
                do {
                    try await clock.sleep(until: started.advanced(by: burstStart))
                } catch {
                    return
                }

                note("burst \(index + 1) fired, \(burst.beats.count) beats")

                for beat in burst.beats {
                    do {
                        try await clock.sleep(until: started.advanced(by: burstStart + beat.start))
                    } catch {
                        return
                    }
                    cues.play(beat)
                }
            }

            // The last beat's purr runs to the end of its phase; releasing the
            // runtime under it would truncate the very taps being measured.
            if let lastStart = DiscreetCadence.burstStarts.last, let lastBeat = burst.beats.last {
                try? await clock
                    .sleep(until: started
                        .advanced(by: lastStart + lastBeat.start + lastBeat.duration))
            }
            cues.stop()

            note("cadence complete")
            release()
        }

        /// Hands the runtime back. Separate from `end()` so the run can finish
        /// without cancelling the task it is the last statement of.
        ///
        /// No builder was ever attached, so ending the session leaves nothing
        /// in Health — mindful minutes stay the app's only write, and no
        /// "Mind & Body workout" appears beside a breathing practice.
        private func release() {
            session?.end()
            session = nil
            isRunning = false
        }

        private func note(_ what: String) {
            Self.logger.notice("\(what, privacy: .public)")
            log.append(Entry(id: log.count, elapsed: elapsed, what: what))
        }
    }

    /// Mirrors `ExtendedRuntime`'s isolation dance: HealthKit calls these on its
    /// own queue and the protocol carries no isolation, so the ones that touch
    /// state hop explicitly.
    extension DiscreetSpike: HKWorkoutSessionDelegate {
        nonisolated func workoutSession(
            _: HKWorkoutSession,
            didChangeTo toState: HKWorkoutSessionState,
            from _: HKWorkoutSessionState,
            date _: Date
        ) {
            // The state is the answer to the runtime question, so it is spelt
            // out rather than logged as a raw value somebody then has to look
            // up on a watch screen.
            let state = switch toState {
            case .notStarted: "not started"
            case .prepared: "prepared"
            case .running: "running"
            case .paused: "paused"
            case .stopped: "stopped"
            case .ended: "ended"
            @unknown default: "unknown (\(toState.rawValue))"
            }

            Task { @MainActor in self.note("workout session \(state)") }
        }

        nonisolated func workoutSession(
            _: HKWorkoutSession,
            didFailWithError error: any Error
        ) {
            // The whole error, described: this is the finding the run exists
            // to collect, and the note is already logged public.
            let cause = String(describing: error)
            Task { @MainActor in
                self.note("workout session failed: \(cause)")
            }
        }
    }

    /// The spike's face: a button, a clock, and the log to read afterwards.
    ///
    /// Start it, lower your wrist, and sit through half an hour without looking.
    /// What it is asking you to notice is which bursts you *felt*; the list is
    /// what the app believed it did, and the two disagreeing is the finding.
    struct DiscreetSpikeView: View {
        let catalogue: TechniqueListModel

        @Environment(WatchSettings.self) private var settings
        @State private var spike = DiscreetSpike()

        /// Coherent breathing, because it is what discreet mode is for: the
        /// gentlest pace in the catalogue and the one whose six breaths come to
        /// about a minute.
        private static let slug = "coherent-breathing"

        var body: some View {
            List {
                Section {
                    control
                    elapsed
                } header: {
                    Text(settings.playsHaptics ? "Haptics on" : "Haptics OFF — turn them on")
                }

                if !spike.log.isEmpty {
                    Section("Log") {
                        ForEach(spike.log) { entry in
                            LabeledContent(
                                entry.what,
                                value: entry.elapsed.formatted(.time(pattern: .minuteSecond))
                            )
                            .font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle("Discreet spike")
        }

        @ViewBuilder
        private var control: some View {
            if spike.isRunning {
                Button("End", role: .destructive) { spike.end() }
            } else if let technique {
                Button("Start 30 min") {
                    spike.start(
                        technique: technique,
                        cues: WatchHapticController(settings: settings)
                    )
                }
            } else {
                Text("Waiting for the catalogue")
                    .font(.caption2)
            }
        }

        private var elapsed: some View {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                LabeledContent(
                    "Elapsed",
                    value: spike.elapsed.formatted(.time(pattern: .minuteSecond))
                )
                .font(.caption2)
            }
        }

        private var technique: Technique? {
            guard case let .loaded(techniques) = catalogue.state else { return nil }
            return techniques.first { $0.slug == Self.slug }
        }
    }
#endif
