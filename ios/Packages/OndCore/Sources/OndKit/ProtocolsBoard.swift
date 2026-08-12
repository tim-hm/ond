import Foundation

/// The Protocols tab, as a value: the named moments, and the rungs of Start
/// here.
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
/// server. `Routes.none` is a supported input, not a degraded one: the routes
/// have no bundled seed, so a first launch that cannot reach the server holds an
/// empty board by design and the tab says so.
public struct ProtocolsBoard: Sendable, Hashable {
    /// Every occasion the catalogue can resolve, in seeded order.
    ///
    /// `protocols` rather than `occasions` because this is the tab's word for
    /// them; the domain keeps `Occasion`, on the wire and in every identifier,
    /// and only the interface was renamed.
    public let protocols: [DialStop]

    /// The Start here progression, in curated order. Each rung's `summary` is
    /// the note that makes the order a progression rather than a list.
    public let startHere: [DialStop]

    /// Whether the board has nothing at all to draw — the first-launch-offline
    /// state, and the one the tab answers with `ContentUnavailableView`.
    public var isEmpty: Bool {
        protocols.isEmpty && startHere.isEmpty
    }

    /// - Parameters:
    ///   - techniques: the catalogue, in its own order.
    ///   - routes: the occasions and the progression, as they last arrived.
    ///   - dialled: what this person dialled themselves, keyed by slug. Passed
    ///     in rather than reached for, so this stays pure — and passed at all
    ///     because a row states a length, which the session it starts then has
    ///     to keep.
    public init(
        techniques: [Technique],
        routes: Routes,
        dialled: [String: TechniqueOverrides] = [:]
    ) {
        let bySlug = DialStop.indexed(techniques)

        self.init(
            protocols: DialStop.occasions(of: routes, resolvedBy: bySlug, dialled: dialled),
            startHere: DialStop.steps(of: routes, resolvedBy: bySlug, dialled: dialled)
        )
    }

    private init(protocols: [DialStop], startHere: [DialStop]) {
        self.protocols = protocols
        self.startHere = startHere
    }

    /// The board narrowed to one goal, or the whole of it where no goal is
    /// chosen.
    ///
    /// A fold rather than a filter written into the view, for the reason the
    /// join is here at all: the pills sit over two screens, and "what does an
    /// active goal hide" is a rule about the board rather than about either
    /// layout. Both sections narrow together — a goal that leaves Start here
    /// showing every rung while the moments thinned out would read as a filter
    /// that half worked.
    ///
    /// `DialStop.goal` rather than the technique's, so an occasion is filtered
    /// by what the moment is for. The two disagree on purpose: a moment borrows
    /// a goal so that what it is for cannot move because a technique was
    /// re-grouped.
    public func filtered(by goal: TechniqueGoal?) -> Self {
        guard let goal else { return self }

        return Self(
            protocols: protocols.filter { $0.goal == goal },
            startHere: startHere.filter { $0.goal == goal }
        )
    }

    /// The goals this board can actually narrow to, in `TechniqueGoal`'s own
    /// order — what the pill row is drawn from.
    ///
    /// Ordered by the enum rather than by the routes, on
    /// `TechniqueGoal.present(in:)`'s reasoning: nothing reshuffles under
    /// somebody who has learned where sleep sits.
    public var goals: [TechniqueGoal] {
        let present = Set((protocols + startHere).map(\.goal))
        return TechniqueGoal.allCases.filter(present.contains)
    }
}
