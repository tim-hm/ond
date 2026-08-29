import Foundation

/// The Protocols tab as a value: the catalogue's occasions joined to techniques.
/// Pure, and given the catalogue rather than a load, so the join's rules — the
/// seeded order, the drop for an unresolvable slug — are testable without a
/// server. `OccasionCatalogue.none` is a supported input: the board is empty,
/// and the tab says so rather than waiting for a fetch that would not fix it.
public struct ProtocolsBoard: Sendable, Hashable {
    /// Every occasion the catalogue can resolve, in seeded order.
    ///
    /// `protocols` rather than `occasions` because this is the tab's word for
    /// them; the domain keeps `Occasion`, on the wire and in every identifier,
    /// and only the interface was renamed.
    public let protocols: [DialStop]

    /// Whether the board has nothing at all to draw — the state the tab answers
    /// with `ContentUnavailableView`.
    public var isEmpty: Bool {
        protocols.isEmpty
    }

    /// - Parameter dialled: what this person dialled themselves, keyed by slug.
    ///   Passed in rather than reached for, so this stays pure — and passed at
    ///   all because a row states a length the session it starts has to keep.
    public init(
        techniques: [Technique],
        occasions: OccasionCatalogue,
        dialled: [String: TechniqueOverrides] = [:]
    ) {
        protocols = DialStop.occasions(
            of: occasions,
            resolvedBy: DialStop.indexed(techniques),
            dialled: dialled
        )
    }

    /// The protocols narrowed to one goal, or all of them where no goal is
    /// chosen. Filtered on `DialStop.goal`, not the technique's — the two
    /// disagree on purpose: a moment borrows a goal so that what it is for
    /// cannot move because a technique was re-grouped.
    public func filtered(by goal: TechniqueGoal?) -> [DialStop] {
        guard let goal else { return protocols }

        return protocols.filter { $0.goal == goal }
    }

    /// The protocols only one kind of device can deliver. Here rather than as a
    /// filter in the wrist's view, so the watch reads the same join the phone
    /// does — a hand-rolled second join once put a second copy of the drop rule
    /// on the other device.
    public func delivered(on surface: DeliverySurface) -> [DialStop] {
        protocols.filter { $0.surface == surface }
    }

    /// The goals this board can narrow to — what the pill row is drawn from.
    /// Ordered by the enum rather than by the occasions, on
    /// `TechniqueGoal.present(in:)`'s reasoning: nothing reshuffles under
    /// somebody who has learned where sleep sits.
    public var goals: [TechniqueGoal] {
        let present = Set(protocols.map(\.goal))
        return TechniqueGoal.allCases.filter(present.contains)
    }
}
