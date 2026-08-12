import Foundation
import OndKit
import os
import WatchConnectivity

/// The phone's side of the pairing: it tells the watch who this person is, and
/// listens for the two things only the wrist can say.
///
/// Everything durable still runs the other way — to the server, from both
/// devices — and this link never carries a session record. What it carries is
/// identity out, which the watch must never mint for itself; the best
/// controlled pause out, measured on a screen the wrist does not have; a
/// session order out, because `startWatchApp` launches the watch app and says
/// nothing; and, back, whether the wrist took that order up, what the wearer's
/// heart is doing while it wears the sensor for a session running here, and
/// whether the session it ran itself has finished.
///
/// Two channels for the two directions, chosen by what a lost message costs.
/// The outbound half is `applicationContext`: state, last-value-wins, replayed
/// whenever the watch next runs, so a phone sending into a watch that is off
/// charge loses nothing. The inbound half is messages, because both are events
/// with a clock on them — the ack answers a sheet that is open right now, and
/// the completion notice is only worth acting on for as long as this install
/// wants the session it names.
///
/// Everything that is not `WCSession` lives in `OndKit`: `WatchHandoffOutbox`
/// decides what is worth sending and remembers what got through,
/// `WristLaunchModel` runs the order exchange, `PulseMonitor` arranges the
/// readings and answers each one, and `JourneyModel` answers the completion
/// notice. This type is the radio around them.
@MainActor
final class WatchLink: NSObject {
    private static let logger = Logger(category: "watch-link")

    private let outbox: WatchHandoffOutbox
    /// What the wrist's answers are handed to. Set once the scene has composed
    /// them, because the link is built in `init` and they are not — a message
    /// arriving before then is one nobody is waiting for.
    private var launches: WristLaunchModel?
    private var journey: JourneyModel?
    private var pulse: PulseMonitor?

    init(outbox: WatchHandoffOutbox) {
        self.outbox = outbox
    }

    /// Hands over the three models the wrist's messages resolve to.
    ///
    /// Injected rather than passed to `init` because two of them are built over
    /// this link's own `push`, so the set cannot be constructed in one breath.
    /// Called once, from the composition root, and those models hold this link
    /// weakly so the two do not retain each other.
    func route(launches: WristLaunchModel, pulse: PulseMonitor, journey: JourneyModel) {
        self.launches = launches
        self.pulse = pulse
        self.journey = journey
    }

    /// Activates the session if it needs it, and sends the current context.
    ///
    /// Safe and cheap to call on every foreground, which is how the phone keeps
    /// a mirrored personal best from going stale: `updateApplicationContext`
    /// overwrites rather than queues, and an unpaired phone drops out at the
    /// first guard.
    func push() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }

        guard session.activationState == .activated else {
            // The activation callback sends the first context. Activating twice
            // is harmless, and doing it here is what covers the launch where
            // nothing else would.
            session.activate()
            return
        }

        Task { await send() }
    }

    /// Hands over whatever the outbox says is outstanding.
    ///
    /// A pairing that goes away between the guard and the call — somebody
    /// unpairing their watch mid-launch — throws, which the outbox reads as
    /// undelivered. The guard is there to skip a read of the score file that
    /// would go nowhere, not to make the send safe.
    private func send() async {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }

        do {
            try await outbox.handOver { handoff in
                try session.updateApplicationContext(handoff.dictionary)
            }
        } catch {
            // Nothing to retry and nothing to tell anyone: the context stays
            // outstanding, the next foreground offers it again, and until then
            // the watch works anonymously by design.
            Self.logger
                .notice("watch handoff deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The sheet's answer, if a sheet is still waiting for one.
    private func acknowledge(_ ack: WatchOrderAck) {
        launches?.acknowledge(ack)
    }

    /// Asks the server for history again, because another device has just added
    /// to it. The record itself never rides this channel — the notice only says
    /// there is something to fetch, which this install's restore had stopped
    /// asking about for the rest of the launch.
    private func adopt(_: WatchSessionNotice) {
        Self.logger.notice("the wrist finished an ordered session")
        Task { await journey?.syncFromWrist() }
    }
}

/// The delegate methods arrive off the main actor, so each one hops rather than
/// doing work where it lands. `WCSession` itself is not `Sendable` and is never
/// captured across the hop — the shared instance is read again on the far side.
/// The `[String: Any]` payloads are decoded on the queue they land on, which is
/// what makes the hop carry a `Sendable` value.
extension WatchLink: WCSessionDelegate {
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error _: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in await self.send() }
    }

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    /// Somebody switched watches. The documented response is to reactivate, so
    /// the new one receives the context the old one had.
    nonisolated func sessionDidDeactivate(_: WCSession) {
        Task { @MainActor in WCSession.default.activate() }
    }

    /// The wrist's live answer to an order it has just been given.
    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        guard let ack = WatchOrderAck(dictionary: message) else { return }
        Task { @MainActor in self.acknowledge(ack) }
    }

    /// A heart-rate reading, which is the one inbound message that gets an answer
    /// rather than merely arriving.
    ///
    /// The reply is what ends the sharing — see `WatchPulseReply` — so a message
    /// this phone cannot read is still answered, with a no. Silence here would
    /// leave a wrist waiting out its whole minute for every unreadable payload.
    nonisolated func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let answer = PulseAnswer(reply: replyHandler)
        guard let pulse = WatchPulse(dictionary: message) else {
            answer.send(isWanted: false)
            return
        }

        Task { @MainActor in answer.send(isWanted: self.pulse?.receive(pulse) ?? false) }
    }

    /// The queued half: the notice that an ordered session has ended, which the
    /// wrist sends whether or not this phone was reachable at the time.
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let notice = WatchSessionNotice(dictionary: userInfo) else { return }
        Task { @MainActor in self.adopt(notice) }
    }
}

/// Carries WatchConnectivity's reply block from the queue it arrives on to the
/// actor that knows the answer.
///
/// A wrapper because the two ends disagree and neither can move: the block is
/// imported with no concurrency annotations, so it is not `Sendable` — capturing
/// it in the hop directly is "sending 'replyHandler' risks causing data races" —
/// and the answer is main-actor state, so the hop is not optional either.
///
/// SAFETY: the block is invoked exactly once and from exactly one place — the
/// task in `didReceiveMessage` above, or the early return beside it — and
/// WatchConnectivity places no thread requirement on it. What the wrapper cannot
/// promise, its one call site does.
private struct PulseAnswer: @unchecked Sendable {
    let reply: ([String: Any]) -> Void

    func send(isWanted: Bool) {
        reply(WatchPulseReply(isWanted: isWanted).dictionary)
    }
}
