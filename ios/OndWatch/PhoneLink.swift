import Foundation
import OndKit
import os
import WatchConnectivity

/// The watch's side of the pairing: it listens, and answers only about the
/// sessions the phone asked for.
///
/// Most of what arrives is state the wrist cannot derive — the anonymous
/// identity, which this app must never mint for itself, and the best controlled
/// pause, measured on a screen the watch does not have. Nothing here blocks: a
/// watch that has never seen its phone still shows the catalogue, still records
/// sessions locally, and simply carries an unacknowledged sync queue until an
/// identity arrives.
///
/// What it also sends are the things only this device can know: whether it took
/// up an order the phone placed, whether that session has finished, and — while
/// the sensor is lent to a session running on the phone — what the wearer's heart
/// is doing. None of it is durable, since the record goes to the server as every
/// other one does, so a message lost costs the phone a sentence or a badge, never
/// a session.
///
/// The radio and nothing else. What a context *means* — provisioning the
/// identity, admitting an order once, keeping a mirrored best a later context
/// does not carry — is `OndKit`'s `WatchHandoffInbox`, which is also what the
/// rest of the app observes.
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

    /// Starts listening. Called once, from the app's root task.
    ///
    /// Activation also makes `receivedApplicationContext` readable, which is
    /// what covers the ordinary case: the phone sent its context while this app
    /// was not running, so there is nothing to be delivered — only something
    /// already waiting.
    func activate() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Tells the phone whether this wrist took up an order.
    ///
    /// A live message, because a sheet on the phone is waiting for it right now
    /// — and one is only ever sent from a watch app the order just brought to
    /// the front, which is the state `sendMessage` needs. Failure is silence by
    /// design: the phone's own timeout says the same thing a beat later, and
    /// there is nothing on this screen a person could do about a radio.
    func acknowledge(_ ack: WatchOrderAck) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        session.sendMessage(ack.dictionary, replyHandler: nil) { error in
            Self.logger
                .notice("the order ack was lost: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Hands one heart-rate reading to the phone, and brings back whether it
    /// still wants them.
    ///
    /// A live message with a reply, which is the one exchange in the pairing that
    /// needs an answer rather than merely benefiting from one: nothing else can
    /// tell this wrist that the session it is wearing the sensor for has ended.
    /// See `WatchPulseReply` for why the answer rides here rather than arriving
    /// as a message of its own.
    ///
    /// - Returns: false for a refusal, an unreadable answer, a phone out of
    ///   range, and a reading that never arrived. `PulseRelay` treats all four
    ///   the same way, because from a wrist they are the same thing.
    func share(_ pulse: WatchPulse) async -> Bool {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return false }

        return await withCheckedContinuation { continuation in
            // Exactly one of the two handlers runs — WatchConnectivity's own
            // contract, and what makes a checked continuation safe here.
            session.sendMessage(pulse.dictionary) { reply in
                continuation
                    .resume(returning: WatchPulseReply(dictionary: reply)?.isWanted ?? false)
            } errorHandler: { error in
                Self.logger.notice(
                    "a reading was not delivered: \(error.localizedDescription, privacy: .public)"
                )
                continuation.resume(returning: false)
            }
        }
    }

    /// Tells the phone an ordered session has finished, so it can ask the
    /// server for the record.
    ///
    /// Queued rather than live: a discreet session ends up to half an hour
    /// after the phone stopped watching, quite possibly in another room, and a
    /// notice that waits out the walk back still means exactly what it meant.
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
