import Foundation

/// The Protocols tab, as a value: the named moments.
///
/// The routing layer joined to the catalogue and nothing else. What the tab used
/// to be — one band of a dial that also held every exercise — mixed two
/// questions: "what is the app for right now" and "what has the app got". The
/// second is the Exercises tab's, two icons away, and a protocol is the answer
/// to the first: a moment somebody recognises, prescribing an exercise, at a
/// length and a loudness the moment asks for.
///
/// Pure, and given the catalogue rather than a load, so the join's rules — the
/// seeded order, the drop for an unresolvable slug — are testable without a
/// server. `OccasionCatalogue.none` is a supported input, not a degraded one: a
/// build whose bundled export could not be read holds an empty board, and the
/// tab says so rather than waiting for a fetch that would not fix it.
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

    /// - Parameters:
    ///   - techniques: the catalogue, in its own order.
    ///   - occasions: the occasions, as they last arrived.
    ///   - dialled: what this person dialled themselves, keyed by slug. Passed
    ///     in rather than reached for, so this stays pure — and passed at all
    ///     because a row states a length, which the session it starts then has
    ///     to keep.
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
    /// chosen.
    ///
    /// `DialStop.goal` rather than the technique's, so an occasion is filtered
    /// by what the moment is for. The two disagree on purpose: a moment borrows
    /// a goal so that what it is for cannot move because a technique was
    /// re-grouped.
    public func filtered(by goal: TechniqueGoal?) -> [DialStop] {
        guard let goal else { return protocols }

        return protocols.filter { $0.goal == goal }
    }

    /// The protocols only one kind of device can deliver.
    ///
    /// The wrist's whole screen: it lists the discreet ones, because those are
    /// the promise only it can keep, and a full-screen protocol on a watch would
    /// be offering a figure and a voice it does not have. Here rather than as a
    /// filter over `protocols` in that view, so the wrist reads the same join
    /// the phone does instead of hand-rolling a second one — which is what it
    /// did, and what put a second copy of the drop rule on the other device.
    public func delivered(on surface: DeliverySurface) -> [DialStop] {
        protocols.filter { $0.surface == surface }
    }

    /// The goals this board can actually narrow to, in `TechniqueGoal`'s own
    /// order — what the pill row is drawn from.
    ///
    /// Ordered by the enum rather than by the occasions, on
    /// `TechniqueGoal.present(in:)`'s reasoning: nothing reshuffles under
    /// somebody who has learned where sleep sits.
    public var goals: [TechniqueGoal] {
        let present = Set(protocols.map(\.goal))
        return TechniqueGoal.allCases.filter(present.contains)
    }
}
