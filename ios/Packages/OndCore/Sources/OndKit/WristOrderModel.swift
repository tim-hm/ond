import Foundation
import Observation
import os

/// What an order the wrist took up puts on its screen. The two errands
/// produce two screens with almost nothing in common; what they share is
/// that the wrist is engaged, there is exactly one, and it is keyed to the
/// order that asked for it.
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

/// The wrist's half of the handoff: what an order the phone placed resolves
/// to, and the answer sent back. `WristLaunchModel`'s mirror, here because
/// the watch target has no test bundle. It answers every order it is handed:
/// the phone's sheet waits on exactly one message, and the failure this
/// prevents is the wrist deciding something and saying nothing.
@MainActor
@Observable
public final class WristOrderModel {
    /// What the wrist is engaged in, or nil. Set only for an order taken up.
    public private(set) var engagement: WristEngagement?

    private static let logger = Logger(category: "watch-link")

    private let catalogue: TechniqueListModel
    private let occasions: OccasionCatalogueModel
    /// Whether the wrist is already mid-session, however it was started. A
    /// closure because the authority is the watch target's workout runtime.
    /// It must answer for a session, not a workout: the phone's launch takes
    /// a workout budget before any session exists, and a wrist answering "a
    /// workout is running" declined every order until `WorkoutRuntime.isClaimed`.
    private let isBusy: @MainActor () -> Bool

    /// The order being resolved right now, if one is — the guard that makes
    /// `take(up:)` single-flight across its own suspension. See there.
    private var resolving: UUID?
    private let answer: @MainActor (WatchOrderAck) -> Void

    /// - Parameters:
    ///   - catalogue: what the ordered technique slug is resolved against.
    ///   - occasions: where the occasion's name comes from — see `take(up:)`.
    ///   - isBusy: whether a session is already running on this wrist.
    ///   - answer: sends the ack. A closure so this model needs no radio.
    public init(
        catalogue: TechniqueListModel,
        occasions: OccasionCatalogueModel,
        isBusy: @escaping @MainActor () -> Bool,
        answer: @escaping @MainActor (WatchOrderAck) -> Void
    ) {
        self.catalogue = catalogue
        self.occasions = occasions
        self.isBusy = isBusy
        self.answer = answer
    }

    /// Takes up an order, or declines it — and says which, either way. A
    /// wrist already engaged declines: two cadences under one runtime would
    /// tap over each other, and the first screen to go away would release
    /// the workout budget from under the other. The same no covers a pulse
    /// request reaching a wrist mid-session — breathing outranks a badge.
    public func take(up order: WatchSessionOrder) async {
        guard !isBusy(), engagement == nil, resolving == nil else {
            // Logged because it is otherwise invisible: a declined order looks,
            // from both devices, exactly like an order nothing ever answered —
            // the watch stays on whatever screen it was showing and the phone
            // reports that the wrist did not take it up. One line here is the
            // difference between reading a log and reading the source.
            Self.logger.notice("declined an order: this wrist is already engaged")
            answer(WatchOrderAck(orderId: order.id, accepted: false))
            return
        }

        // Claimed before the await: resolving can suspend on a cold catalogue
        // fetch, and the phone has two independent order producers. Two
        // orders arriving inside that window would both clear the guard, both
        // be told yes, and the second would overwrite the first's screen.
        resolving = order.id
        defer { resolving = nil }

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
    /// Only the breathing errand waits, and only for the catalogue, which
    /// decides the answer; the occasions supply a name and are never waited
    /// for — this sits inside the phone's ten-second window. A pulse share
    /// checks no grant: HealthKit never reports a refused read anyway.
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
            occasions: occasions.available.occasions
        )
    }
}
