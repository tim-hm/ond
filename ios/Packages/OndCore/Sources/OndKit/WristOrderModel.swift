import Foundation
import Observation
import os

/// What an order the wrist took up puts on its screen.
///
/// The two errands produce two screens with almost nothing in common — one
/// breathes a resolved technique and keeps a record, the other shows a number and
/// keeps nothing — so what they share is only this: the wrist is engaged, there is
/// exactly one of them, and it is keyed to the order that asked for it.
public enum WristEngagement: Sendable, Equatable, Identifiable {
    /// A session to breathe here, resolved against this watch's catalogue.
    case breathe(OrderedMoment)
    /// The sensor, worn for a session running on the phone.
    case sharePulse(WatchSessionOrder)

    /// The order's id, so a `sheet(item:)` presenting this is keyed to the
    /// exchange rather than to whatever it resolved to.
    public var id: UUID {
        switch self {
        case let .breathe(moment): moment.id
        case let .sharePulse(order): order.id
        }
    }
}

/// The wrist's half of the handoff: what an order the phone placed resolves to,
/// and the answer sent back.
///
/// `WristLaunchModel`'s mirror, and here for the same reason it is: the sequence
/// is where the states are. Resolve, decide accepted or declined, answer once,
/// present at most one thing — four decisions with three ways to be wrong, none
/// of them testable in the watch target, which has no test bundle.
///
/// It answers every order it is handed. A phone with a sheet open is waiting on
/// exactly one message, and the failure this exists to prevent is the wrist
/// deciding something and saying nothing.
@MainActor
@Observable
public final class WristOrderModel {
    /// What the wrist is engaged in, or nil. Set only for an order taken up.
    public private(set) var engagement: WristEngagement?

    private static let logger = Logger(category: "watch-link")

    private let catalogue: TechniqueListModel
    private let routes: RoutesModel
    /// Whether the wrist is already mid-session, whichever way that session was
    /// started. A closure rather than a state this model keeps, because the
    /// authority is the workout runtime the watch target owns — and a session
    /// somebody started by hand on the wrist counts every bit as much as one the
    /// phone ordered.
    ///
    /// It must answer for a session, not for a workout. The launch the phone makes
    /// takes a workout budget of its own, before there is any session to spend it
    /// on, so a wrist that answered "a workout is running" would decline every
    /// order the phone ever sent it — which is precisely what it did until
    /// `WorkoutRuntime.isClaimed` existed to tell the two apart.
    private let isBusy: @MainActor () -> Bool
    private let answer: @MainActor (WatchOrderAck) -> Void

    /// - Parameters:
    ///   - catalogue: what the ordered technique slug is resolved against.
    ///   - routes: where the occasion's name comes from, read without waiting —
    ///     see `take(up:)`.
    ///   - isBusy: whether a session is already running on this wrist.
    ///   - answer: sends the ack. A closure so this model needs no radio.
    public init(
        catalogue: TechniqueListModel,
        routes: RoutesModel,
        isBusy: @escaping @MainActor () -> Bool,
        answer: @escaping @MainActor (WatchOrderAck) -> Void
    ) {
        self.catalogue = catalogue
        self.routes = routes
        self.isBusy = isBusy
        self.answer = answer
    }

    /// Takes up an order, or declines it — and says which, either way.
    ///
    /// A wrist already engaged declines. Two cadences under one runtime would tap
    /// over each other, and the first screen to go away would release the workout
    /// budget from under the other; the phone hears no and shows the sentence that
    /// names the way out. The same answer covers a phone asking for readings from
    /// a wrist that is mid-session: the budget is spoken for, and the session
    /// somebody is breathing outranks a badge.
    public func take(up order: WatchSessionOrder) async {
        guard !isBusy(), engagement == nil else {
            // Logged because it is otherwise invisible: a declined order looks,
            // from both devices, exactly like an order nothing ever answered —
            // the watch stays on whatever screen it was showing and the phone
            // reports that the wrist did not take it up. One line here is the
            // difference between reading a log and reading the source.
            Self.logger.notice("declined an order: this wrist is already engaged")
            answer(WatchOrderAck(orderId: order.id, accepted: false))
            return
        }

        let engagement = await resolve(order)
        // The engagement before the ack, so the phone is never told something is
        // running before the thing that runs it exists.
        self.engagement = engagement
        answer(WatchOrderAck(orderId: order.id, accepted: engagement != nil))
        if engagement == nil {
            Self.logger.notice("declined an order this build cannot resolve")
        }
    }

    /// Forgets what was presented, so the next order has somewhere to go. Called
    /// as the screen goes away — whatever it was doing has already ended by then,
    /// or ends because it did.
    public func dismiss() {
        engagement = nil
    }

    /// What this order comes to on this wrist, or nil for one it cannot keep.
    ///
    /// Only the breathing errand waits for anything, and it waits because the
    /// catalogue decides the answer: an order naming a technique this build does
    /// not hold cannot be run, and `loadIfNeeded` falls back to the bundled seed,
    /// so it resolves with no signal at all. The routes are read as they stand and
    /// never waited for — they supply only the occasion's name, which
    /// `OrderedMoment` already falls back on, and this call sits inside the
    /// phone's ten-second window in front of somebody waiting for their wrist.
    ///
    /// Sharing a pulse resolves against nothing. There is no technique to look up
    /// and no grant worth checking first: HealthKit never reports a refused read,
    /// so a wrist that will yield no readings looks exactly like one that will,
    /// and the phone's badge stays empty either way.
    private func resolve(_ order: WatchSessionOrder) async -> WristEngagement? {
        switch order.errand {
        case .breathe:
            await catalogue.loadIfNeeded()
            return breathing(order).map(WristEngagement.breathe)

        case .sharePulse:
            return .sharePulse(order)
        }
    }

    private func breathing(_ order: WatchSessionOrder) -> OrderedMoment? {
        guard case let .loaded(techniques) = catalogue.state else { return nil }

        return OrderedMoment(
            order: order,
            techniques: techniques,
            occasions: routes.available.occasions
        )
    }
}
