import Foundation
import OndKit
import os
import WatchConnectivity

/// The watch's side of the pairing: the radio only — what a context *means*
/// is `WatchHandoffInbox`'s. It receives state the wrist cannot derive (the
/// anonymous identity, which this app must never mint, and the best
/// controlled pause) and sends what only this device knows. Nothing blocks,
/// nothing is durable: a lost message costs a sentence or a badge, never a session.
@MainActor
final class PhoneLink: NSObject {
    /// `nonisolated` because the failure handler below runs on
    /// WatchConnectivity's own queue, not the main actor — a MainActor-isolated
    /// static read from there is the hazard `WorkoutRuntime` declares away for
    /// the same reason.
    private nonisolated static let logger = Logger(category: "watch-link")

    private let inbox: WatchHandoffInbox

    init(inbox: WatchHandoffInbox) {
        self.inbox = inbox
        super.init()
    }

    /// Starts listening. Called once, from the app's root task. Activation
    /// also makes `receivedApplicationContext` readable, which covers the
    /// ordinary case: the phone sent its context while this app was not
    /// running, so nothing is delivered — something is already waiting.
    func activate() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Tells the phone whether this wrist took up an order. A live message: a
    /// sheet on the phone is waiting right now, and one is only sent from an
    /// app the order just fronted, the state `sendMessage` needs. Failure is
    /// silence by design — the phone's own timeout says the same thing a beat
    /// later, and nobody on this screen can do anything about a radio.
    func acknowledge(_ ack: WatchOrderAck) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        session.sendMessage(ack.dictionary, replyHandler: nil) { error in
            Self.logger
                .notice("the order ack was lost: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Hands one heart-rate reading to the phone and brings back what became
    /// of it — the one exchange needing a reply: nothing else can tell this
    /// wrist that the session it lends the sensor to has ended. The reply's
    /// distinction is load-bearing: out of range is not a refusal (read as a
    /// bare no, one lost message ended sharing); an unreadable answer is one.
    func share(_ pulse: WatchPulse) async -> PulseDelivery {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return .undelivered
        }

        return await withCheckedContinuation { continuation in
            // Exactly one of the two handlers runs — WatchConnectivity's own
            // contract, and what makes a checked continuation safe here.
            session.sendMessage(pulse.dictionary) { reply in
                guard let answer = WatchPulseReply(dictionary: reply) else {
                    continuation.resume(returning: .refused)
                    return
                }
                continuation.resume(returning: answer.isWanted ? .wanted : .refused)
            } errorHandler: { error in
                Self.logger.debug(
                    "a reading was not delivered: \(error.localizedDescription, privacy: .public)"
                )
                continuation.resume(returning: .undelivered)
            }
        }
    }

    /// Tells the phone an ordered session has finished, so it can ask the
    /// server for the record. Queued rather than live: a discreet session
    /// ends up to half an hour after the phone stopped watching, and a notice
    /// that waits out the walk back still means exactly what it meant.
    func report(_ notice: WatchSessionNotice) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        session.transferUserInfo(notice.dictionary)
    }
}

/// The delegate methods arrive off the main actor with an untyped dictionary.
/// Each one decodes on the queue it lands on — `WatchHandoff` is `Sendable`,
/// where the `[String: Any]` it came from is not — and hops with the result.
extension PhoneLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error _: (any Error)?
    ) {
        guard activationState == .activated,
              let handoff = WatchHandoff(dictionary: session.receivedApplicationContext)
        else {
            return
        }

        Task { @MainActor in await self.inbox.adopt(handoff) }
    }

    nonisolated func session(
        _: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let handoff = WatchHandoff(dictionary: applicationContext) else { return }
        Task { @MainActor in await self.inbox.adopt(handoff) }
    }
}
