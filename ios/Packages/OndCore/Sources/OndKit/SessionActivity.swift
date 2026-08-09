#if os(iOS)
    import ActivityKit
    import Foundation
    import Observation
    import os

    /// The running session's presence on the lock screen and in the Dynamic
    /// Island: it requests the Activity, keeps it in step with the session, and
    /// ends it when the session does.
    ///
    /// **Why it observes rather than being told.** The obvious wiring is a
    /// `.onChange` on the session view, and it is wrong here: the surface this
    /// drives exists precisely for the minutes the app is *not* on screen, and a
    /// backgrounded app stops evaluating view bodies. `withObservationTracking`
    /// is a callback on the model's own registrar, so it fires with the phone in
    /// a pocket exactly as it does with it in a hand. Nothing about the session
    /// engine changes to accommodate this, which also keeps it off the watch,
    /// where there is no ActivityKit at all.
    ///
    /// **Why the Activity is behind a stream.** `Activity` is neither `Sendable`
    /// nor isolated, so it cannot be held on a `@MainActor` property and then
    /// awaited — every call would be sending it out of the actor's region. One
    /// task owns it from request to end and takes redraws through an
    /// `AsyncStream`, which also makes update ordering structural: a phase cue
    /// that arrives out of order is worse than one that arrives late, and there
    /// is now no arrangement in which that can happen.
    ///
    /// **Why there is a `current`.** The lock screen's buttons are App Intents,
    /// and an App Intent is a value the system instantiates from nothing — it
    /// has no way to be handed the session it is about. One process-wide anchor
    /// is the whole of the mechanism, and it is set and cleared by the session
    /// that owns it rather than being a store anything can write.
    ///
    /// **It is silent.** Every update goes out with no alert configuration, so
    /// the lock screen never makes a sound or a banner for a breath. This is a
    /// calm app and the lock screen is the loudest surface it has.
    @MainActor
    public final class SessionActivity {
        /// The one session an App Intent can reach, or nil when none is running.
        public private(set) static var current: SessionActivity?

        private nonisolated static let logger = Logger(category: "live-activity")

        private let session: SessionModel
        /// Where each redraw is posted. Finishing it is how the Activity ends.
        private let redraws: AsyncStream<SessionPresence>.Continuation

        private init(session: SessionModel, showing first: SessionPresence) {
            self.session = session
            // `bufferingNewest(1)` rather than an unbounded buffer: if the
            // system is slow enough that redraws queue, the right thing to show
            // is the phase somebody is in now, never a backlog of the ones they
            // have already breathed.
            let (stream, redraws) = AsyncStream<SessionPresence>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            self.redraws = redraws

            let attributes = SessionActivityAttributes(technique: session.technique)
            Task { await Self.run(stream, opening: first, as: attributes) }
        }

        /// Puts `session` on the lock screen and in the Dynamic Island, replacing
        /// whatever was there.
        ///
        /// Returns nil, having done nothing, when the person has Live Activities
        /// switched off — not a failure worth surfacing, because the session
        /// itself is unaffected and the screen they started it from is still the
        /// screen they are looking at.
        ///
        /// - Parameter session: the session that has just started. Call this
        ///   after `start()`, so there is a phase to show.
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

        /// Stops the running session where it stands, which is what the lock
        /// screen's Pause button asks for.
        ///
        /// The three methods here are the whole surface the intents reach, and
        /// they are static because an App Intent is a value the system builds
        /// from nothing — there is no session it could have been handed. Nothing
        /// running is not a failure: the Activity outlived its process, and the
        /// person is pressing a button on a picture of a session that ended.
        public static func pauseRunningSession() {
            current?.session.pause()
        }

        /// Starts the running session up again — including one iOS paused by
        /// taking the app away, which `SessionModel.resume()` clears.
        public static func resumeRunningSession() {
            current?.session.resume()
        }

        /// Ends the running session, or clears the Activity when there is no
        /// session behind it any more.
        ///
        /// The second half is what makes End the honest button on a stranded
        /// Activity: whatever the state of the world, pressing it leaves the
        /// lock screen empty.
        public static func endRunningSession() async {
            guard let current else {
                await clearStranded()
                return
            }
            current.session.end()
        }

        /// Clears any Activity left behind by a process that went away without
        /// ending one — a crash, or a force quit mid-session.
        ///
        /// The system keeps a Live Activity alive across the death of the app
        /// that requested it, so without this the lock screen would go on asking
        /// somebody to breathe out until it aged out by itself.
        public nonisolated static func clearStranded() async {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        /// Owns the Activity for its whole life: requests it, redraws it as the
        /// stream produces, and ends it when the stream finishes.
        ///
        /// `nonisolated` is the point rather than an optimisation — see the note
        /// on the type. Ended `.immediate` rather than left up for a while: the
        /// summary is in the app, and a cue that outlives the breath it was
        /// cueing is the lock screen still asking somebody to inhale.
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

        /// Re-arms on every change to the phase or the session's status, which
        /// between them are every reason the surface has to redraw.
        ///
        /// `withObservationTracking` is one-shot, so the callback re-arms itself.
        /// The hop through a `Task` is not optional: the callback runs *before*
        /// the property changes, and reading the model from inside it would
        /// answer for the state being left rather than the one being entered.
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
                // Nothing left to show is the session having ended, which is
                // what takes the cue down — and there is nothing left to arm.
                end()
                return
            }

            redraws.yield(presence)
            observe()
        }
    }
#endif
