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
/// What it now also sends are the two events only this device knows: whether it
/// took up an order the phone placed, and whether that session has finished.
/// Neither carries anything durable — the record goes to the server as every
/// other one does — so a message lost costs the phone a sentence, never a
/// session.
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
