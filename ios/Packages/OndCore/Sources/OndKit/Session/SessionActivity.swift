#if os(iOS)
    import ActivityKit
    import Foundation
    import Observation
    import os

    /// The running session's presence on the lock screen and in the Dynamic Island.
    /// It observes the model with `withObservationTracking`, which fires while the
    /// app is backgrounded; view updates do not. One nonisolated task owns the
    /// non-`Sendable` `Activity` and takes redraws through an `AsyncStream`, so
    /// updates cannot arrive out of order. Every update is silent: no alerts.
    @MainActor
    public final class SessionActivity {
        /// The one session an App Intent can reach, or nil when none is running.
        public private(set) static var current: SessionActivity?

        private nonisolated static let logger = Logger(category: "live-activity")

        private let session: SessionModel
        private var updatePolicy: SessionActivityUpdatePolicy
        /// Where each redraw is posted. Finishing it is how the Activity ends.
        private let redraws: AsyncStream<SessionPresence>.Continuation

        private init(session: SessionModel, showing first: SessionPresence) {
            self.session = session
            updatePolicy = SessionActivityUpdatePolicy(
                status: session.status,
                beat: session.describingBeat
            )
            // `bufferingNewest(1)` rather than an unbounded buffer: if the
            // system is slow enough that redraws queue, the right thing to show
            // is the phase somebody is in now, never a backlog of the ones they
            // have already breathed.
            let (stream, redraws) = AsyncStream<SessionPresence>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            self.redraws = redraws

            let attributes = SessionActivityAttributes(of: session)
            Task { await Self.run(stream, opening: first, as: attributes) }
        }

        /// Puts `session` on the lock screen and in the Dynamic Island, replacing
        /// whatever was there. Returns nil, having done nothing, when Live
        /// Activities are switched off — the session itself is unaffected.
        /// Call after `start()`, so there is a phase to show.
        @discardableResult
        public static func begin(for session: SessionModel) -> SessionActivity? {
            current?.end()

            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
            guard let presence = SessionPresence(of: session, at: .now) else { return nil }

            let presentation = SessionActivity(session: session, showing: presence)
            current = presentation
            presentation.observe()
            return presentation
        }

        /// Takes the session off the lock screen, and is safe to call however
        /// many times.
        public func end() {
            if Self.current === self {
                Self.current = nil
            }
            redraws.finish()
        }

        /// Pauses the running session — the lock screen's Pause button. These
        /// static methods are the whole surface the App Intents reach: the
        /// system builds an intent from nothing, so it cannot be handed a
        /// session. No running session is not a failure — the Activity may
        /// have outlived its process.
        public static func pauseRunningSession() {
            current?.session.pause()
        }

        /// Starts the running session up again — including one iOS paused by
        /// taking the app away, which `SessionModel.resume()` clears. Only
        /// offered where ``SessionActivityAttributes/followsYouOut`` says the
        /// session can run out here.
        public static func resumeRunningSession() {
            current?.session.resume()
        }

        /// Ends the retention the person is in — the lock screen's "I'm ready".
        /// An open-ended hold parks the cue loop until `release()`, so without
        /// this a locked phone would count a retention up with no way to
        /// finish it short of unlocking.
        public static func releaseRunningHold() {
            current?.session.release()
        }

        /// Ends the running session, or clears the Activity when there is no
        /// session behind it any more — so pressing End always leaves the lock
        /// screen empty, stranded Activity included.
        public static func endRunningSession() async {
            guard let current else {
                await clearStranded()
                return
            }
            current.session.end()
        }

        /// Clears any Activity left behind by a crash or a force quit
        /// mid-session. The system keeps a Live Activity alive across the death
        /// of the app that requested it, so without this the lock screen would
        /// go on asking somebody to breathe until it aged out by itself.
        public nonisolated static func clearStranded() async {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        /// Owns the Activity for its whole life: requests it, redraws it as the
        /// stream produces, and ends it when the stream finishes. `nonisolated`
        /// is the point, not an optimisation — see the note on the type. Ends
        /// `.immediate` so no cue outlives the breath it was cueing.
        private nonisolated static func run(
            _ redraws: AsyncStream<SessionPresence>,
            opening first: SessionPresence,
            as attributes: SessionActivityAttributes
        ) async {
            let activity: Activity<SessionActivityAttributes>
            do {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: first, staleDate: nil),
                    pushType: nil
                )
            } catch {
                logger.notice(
                    "live activity refused: \(error.localizedDescription, privacy: .public)"
                )
                return
            }

            for await presence in redraws {
                await activity.update(ActivityContent(state: presence, staleDate: nil))
            }

            await activity.end(nil, dismissalPolicy: .immediate)
        }

        /// Re-arms on every change to the phase or the session's status.
        /// `withObservationTracking` is one-shot, so the callback re-arms
        /// itself. The hop through a `Task` is not optional: the callback runs
        /// *before* the property changes, and reading the model inside it would
        /// answer for the state being left, not the one being entered.
        private func observe() {
            withObservationTracking {
                _ = session.status
                _ = session.currentBeat?.id
            } onChange: { [weak self] in
                Task { @MainActor in self?.sessionChanged() }
            }
        }

        /// Redraws for the change that has now landed, and arms the next one.
        private func sessionChanged() {
            guard let presence = SessionPresence(of: session, at: .now) else {
                // The session has ended: take the cue down, arm nothing. Only
                // this place can withdraw the paused notice — a session ended
                // from the lock screen never comes back through `.active`, so
                // the request would otherwise fire, with a sound, over a
                // session that is gone.
                SessionPausedNotice.withdraw()
                end()
                return
            }

            if updatePolicy.shouldPublish(
                status: session.status,
                beat: session.describingBeat
            ) {
                redraws.yield(presence)
            }
            observe()
        }
    }
#endif
