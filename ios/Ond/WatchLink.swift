import Foundation
import OndKit
import os
import WatchConnectivity

/// The phone's side of the pairing; it never carries a session record.
/// Identity, best pause and session orders go out; acks, heart readings and
/// completion notices come back. Outbound rides `applicationContext` — state,
/// last-value-wins, replayed, so a watch off charge loses nothing. Inbound is
/// messages: events with a clock. Only the radio; decisions live in `OndKit`.
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

    /// Hands over the three models the wrist's messages resolve to. Injected
    /// rather than passed to `init` because two of them are built over this
    /// link's own `push`. Called once, from the root; the models hold this
    /// link weakly so the two do not retain each other.
    func route(launches: WristLaunchModel, pulse: PulseMonitor, journey: JourneyModel) {
        self.launches = launches
        self.pulse = pulse
        self.journey = journey
    }

    /// Activates the session if it needs it, and sends the current context.
    /// Safe on every foreground — `updateApplicationContext` overwrites
    /// rather than queues, and an unpaired phone drops out at the first
    /// guard — which is how the mirrored personal best stays fresh.
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

    /// Hands over whatever the outbox says is outstanding. A pairing lost
    /// between the guard and the call throws, which the outbox reads as
    /// undelivered — the guard only skips a pointless read of the score
    /// file; it does not make the send safe.
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

    /// An order's answer, offered to both models that place one — each checks
    /// whether the id is its own, so no registry is needed. Offering it to
    /// one was a bug: a declined sharing order matched nothing and was
    /// dropped, leaving the phone holding an arrangement the wrist had
    /// already refused.
    private func acknowledge(_ ack: WatchOrderAck) {
        launches?.acknowledge(ack)
        pulse?.acknowledge(ack)
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

    /// A heart-rate reading, the one inbound message that gets an answer. The
    /// reply ends the sharing — see `WatchPulseReply` — so an unreadable
    /// message is still answered, with a no; silence would leave the wrist
    /// waiting out its whole minute.
    nonisolated func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // Decoded here rather than after the hop, so the answer has exactly one
        // call site: `WatchPulse` is `Sendable` where the dictionary it came from
        // is not, and an unreadable payload is simply a reading that resolves to
        // no.
        let answer = PulseAnswer(reply: replyHandler)
        let reading = WatchPulse(dictionary: message)

        Task { @MainActor in
            answer.send(isWanted: reading.flatMap { self.pulse?.receive($0) } ?? false)
        }
    }

    /// The queued half: the notice that an ordered session has ended, which the
    /// wrist sends whether or not this phone was reachable at the time.
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let notice = WatchSessionNotice(dictionary: userInfo) else { return }
        Task { @MainActor in self.adopt(notice) }
    }
}

/// Carries WatchConnectivity's reply block — imported non-`Sendable`, so it
/// cannot cross the hop directly — to the main actor that knows the answer.
/// SAFETY: the block is invoked exactly once, from the one call site in
/// `didReceiveMessage` above, and WatchConnectivity places no thread requirement
/// on it. What the wrapper cannot promise, that single call site does.
private struct PulseAnswer: @unchecked Sendable {
    let reply: ([String: Any]) -> Void

    func send(isWanted: Bool) {
        reply(WatchPulseReply(isWanted: isWanted).dictionary)
    }
}
