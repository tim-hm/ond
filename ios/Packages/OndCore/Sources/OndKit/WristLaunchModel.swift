import Foundation
import Observation

/// Drives one handoff from the phone to the wrist: the order out, the launch
/// call, and the ack back — or the admission that nothing answered. The
/// order travels as replayed context state, the ack as a live message lost
/// if nobody listens; a wrist that is off or missing the app produces no
/// event at all, so the timeout turns "nothing happened" into a sentence.
@MainActor
@Observable
public final class WristLaunchModel {
    /// Where the handoff is. Nil is idle — nothing in flight, no sheet.
    public enum Phase: Sendable, Equatable {
        /// The order is placed and the system asked to launch the watch app;
        /// nothing has answered yet.
        case sending
        /// The wrist said yes: the session is running there, and this phone's
        /// part is over.
        case running
        /// The launch was refused, the wrist declined, or the timeout passed
        /// unanswered. One state for all three, because the person's next move
        /// is the same: start it from the watch by hand.
        case failed
        /// Sending a session to the wrist is part of önd+, and this person is
        /// not. Kept apart from [`failed`](Self.failed) because the next move is
        /// the opposite one: nothing went wrong, nothing will work by retrying,
        /// and what is on offer is a subscription rather than a walk to the
        /// watch.
        case locked
    }

    public private(set) var phase: Phase?

    /// How long an unanswered launch may look like progress before it is
    /// called what it is. Long enough for a wrist-side launch and a tap of
    /// radio; far shorter than anybody watches a spinner.
    static let ackTimeout: Duration = .seconds(10)

    private let outbox: WatchHandoffOutbox
    private let push: @MainActor () -> Void
    private let launcher: any WristLaunching
    private let clock: any SessionClock
    /// The order awaiting its ack. The single-flight guard, and the check
    /// every late arrival — an ack, a timeout, a refused launch resuming — is
    /// measured against before it may conclude anything.
    private var pending: WatchSessionOrder?
    /// The exchange in flight, held so `dismiss()` can stop a timeout nobody
    /// is waiting out any more.
    private var exchange: Task<Void, Never>?

    /// The one initialiser that names the clock, internal on `SessionModel`'s
    /// exact terms: outside a test there is only one clock a timeout runs on.
    init(
        outbox: WatchHandoffOutbox,
        launcher: any WristLaunching,
        push: @escaping @MainActor () -> Void,
        clock: any SessionClock
    ) {
        self.outbox = outbox
        self.launcher = launcher
        self.push = push
        self.clock = clock
    }

    /// The public way in, on the system clock. `push` hands the outbox to
    /// the radio — the phone's `WatchLink.push`, as a closure so this model
    /// needs nothing from the app target.
    public convenience init(
        outbox: WatchHandoffOutbox,
        launcher: any WristLaunching,
        push: @escaping @MainActor () -> Void
    ) {
        self.init(outbox: outbox, launcher: launcher, push: push, clock: SystemClock())
    }

    /// Sends one order to the wrist and starts waiting for its answer.
    /// Synchronous, and the phase is set before it returns: the sheet opens
    /// in the same tap, and a nil phase would leave it one frame with nothing
    /// true to say. A second call while one is in flight is a no-op — the
    /// wrist runs one session at a time.
    public func launch(occasionSlug: String, techniqueSlug: String) {
        guard pending == nil else { return }

        let order = WatchSessionOrder(
            id: UUID(),
            errand: .breathe(occasionSlug: occasionSlug, techniqueSlug: techniqueSlug),
            issuedAt: .now
        )
        // The context before the launch: the launch call carries nothing, so
        // the order must already be waiting in the dictionary when the watch
        // app activates. A subscription refusal lands before the phase is
        // set, so the sheet opens on the offer rather than a spinner.
        guard outbox.place(order) else {
            phase = .locked
            return
        }

        // Anchored before anything is awaited: the timeout covers the whole
        // exchange from the moment the order exists, not from wherever the
        // launch call happened to resume.
        let deadline = clock.now.advanced(by: Self.ackTimeout)
        pending = order
        phase = .sending
        push()

        exchange = Task { await self.wait(out: order, until: deadline) }
    }

    /// Asks the system to launch, then waits out the ack. Every step
    /// re-checks that `order` is still the pending one: an ack landing
    /// mid-await concludes the exchange first, and this must not overwrite a
    /// conclusion somebody has already read.
    private func wait(out order: WatchSessionOrder, until deadline: ContinuousClock.Instant) async {
        let launched = await launcher.launchWatchApp()
        guard pending?.id == order.id else { return }
        guard launched else {
            conclude(order, as: .failed)
            return
        }

        // Cancellation lands the same way as expiry, on purpose: a sheet torn
        // down mid-wait still owes the outbox its withdrawal, and `dismiss()`
        // does that itself — leaving nothing pending for this to conclude.
        try? await clock.sleep(until: deadline)
        if pending?.id == order.id {
            conclude(order, as: .failed)
        }
    }

    /// The wrist's answer, arriving over the message channel.
    ///
    /// An id that matches nothing pending is an ack outliving its exchange —
    /// a reply to an order the timeout already gave up on — and concludes
    /// nothing: the person has read the fallback and may be acting on it.
    public func acknowledge(_ ack: WatchOrderAck) {
        guard let pending, ack.orderId == pending.id else { return }
        conclude(pending, as: ack.accepted ? .running : .failed)
    }

    /// The sheet went away. Whatever was in flight is withdrawn, so the next
    /// ordinary context does not carry an order nobody is waiting on.
    public func dismiss() {
        conclude(pending, as: nil)
    }

    /// Ends the exchange, retracting the order from the watch on the way out.
    /// The retraction is why a conclusion pushes: `withdraw` only changes the
    /// next context, the order already sits in the replayed dictionary, and
    /// the ledger honours it for ten minutes — without a push, "Cancel"
    /// cancels nothing. Delivered orders are retracted too, as spent news.
    private func conclude(_ order: WatchSessionOrder?, as outcome: Phase?) {
        if let order {
            outbox.withdraw(order.id)
            push()
        }
        pending = nil
        phase = outcome
        // Cancelled rather than left to expire: the wait's only remaining
        // statement is a guard this conclusion has already failed, and a
        // cancelled sleep releases the wrist's answer path at once.
        exchange?.cancel()
        exchange = nil
    }
}
