import Foundation
import Observation

/// The wrist's half of the handoff: what an order the phone placed resolves to,
/// and the answer sent back.
///
/// `WristLaunchModel`'s mirror, and here for the same reason it is: the sequence
/// is where the states are. Resolve, decide accepted or declined, answer once,
/// present at most one session — four decisions with three ways to be wrong,
/// none of them testable in the watch target, which has no test bundle.
///
/// It answers every order it is handed. A phone with a sheet open is waiting on
/// exactly one message, and the failure this exists to prevent is the wrist
/// deciding something and saying nothing.
@MainActor
@Observable
public final class WristOrderModel {
    /// The session to present, or nil. Set only for an order taken up.
    public private(set) var ordered: OrderedMoment?

    private let catalogue: TechniqueListModel
    private let routes: RoutesModel
    /// Whether the wrist is already mid-session, whichever way that session was
    /// started. A closure rather than a state this model keeps, because the
    /// authority is the workout runtime the watch target owns — and a session
    /// somebody started by hand on the wrist counts every bit as much as one the
    /// phone ordered.
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
    /// The catalogue is awaited because it decides the answer: an order naming a
    /// technique this build does not hold cannot be run, and `loadIfNeeded`
    /// falls back to the bundled seed, so it resolves with no signal at all. The
    /// routes are read as they stand and never waited for. They supply only the
    /// occasion's name, which `OrderedMoment` already falls back on — and this
    /// call sits inside the phone's ten-second ack window, in front of a person
    /// waiting for their wrist to start tapping.
    ///
    /// A wrist already mid-session declines. Two cadences under one runtime
    /// would tap over each other, and the first screen to go away would release
    /// the workout budget from under the other; the phone hears no and shows the
    /// sentence that names the way out.
    public func take(up order: WatchSessionOrder) async {
        guard !isBusy(), ordered == nil else {
            answer(WatchOrderAck(orderId: order.id, accepted: false))
            return
        }

        await catalogue.loadIfNeeded()

        let moment = resolve(order)
        // The session before the ack, so the phone is never told a session is
        // running before the thing that runs it exists.
        ordered = moment
        answer(WatchOrderAck(orderId: order.id, accepted: moment != nil))
    }

    /// Forgets the presented session, so the next order has somewhere to go.
    /// Called as the screen goes away — the session itself has already ended by
    /// then, or ends because it did.
    public func dismiss() {
        ordered = nil
    }

    private func resolve(_ order: WatchSessionOrder) -> OrderedMoment? {
        guard case let .loaded(techniques) = catalogue.state else { return nil }

        return OrderedMoment(
            order: order,
            techniques: techniques,
            occasions: routes.available.occasions
        )
    }
}
