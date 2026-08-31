import Foundation

/// One segment of a breathing cycle.
///
/// The raw value is a stored key — the catalogue is cached on disk so the app
/// can breathe offline — and a synthesised case name is not a key that should
/// survive a refactor.
public enum PhaseKind: String, Sendable, Hashable, Codable {
    case inhale
    case holdIn
    case exhale
    case holdOut
}

/// What the breath does in one phase, and — where air is moving — where it
/// goes. The passage rides on the movement, so a hold through a nostril
/// cannot be written down: the shape `ond.v1.DraftPhase`'s oneof has, which
/// keeps decoding a served `Phase` total. Four cases mirror `PhaseKind`
/// because `kind` is what every cue, haptic and colour switches on.
public enum Breath: Sendable, Hashable, Codable {
    case inhale(through: Passage)
    case holdIn
    case exhale(through: Passage)
    case holdOut

    public var kind: PhaseKind {
        switch self {
        case .inhale: .inhale
        case .holdIn: .holdIn
        case .exhale: .exhale
        case .holdOut: .holdOut
        }
    }

    /// Where the air goes, or nil for a hold.
    public var passage: Passage? {
        switch self {
        case let .inhale(passage), let .exhale(passage): passage
        case .holdIn, .holdOut: nil
        }
    }

    /// The breath a `kind` and a passage describe — the one way onto this type
    /// from the pair the wire and the database carry separately. Total in both
    /// arguments: a hold arriving with a passage resolves to a hold, because
    /// the case it maps to has no room for one.
    public init(kind: PhaseKind, through passage: Passage) {
        switch kind {
        case .inhale: self = .inhale(through: passage)
        case .holdIn: self = .holdIn
        case .exhale: self = .exhale(through: passage)
        case .holdOut: self = .holdOut
        }
    }
}

/// Written out because a synthesised `Codable` keys the cache on case names
/// and the `through:` label, which a rename changes with no compile error.
/// `kind` and `passage` are the pair the wire and the export already carry.
/// Adopting this shape drops the phase caches earlier builds wrote, once.
/// `StoredIdentifierShapeTests` pins it.
public extension Breath {
    private enum CodingKeys: String, CodingKey {
        case kind
        case passage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(PhaseKind.self, forKey: .kind)

        switch kind {
        case .holdIn: self = .holdIn
        case .holdOut: self = .holdOut
        case .inhale, .exhale:
            // A moving breath with no passage is a value this type cannot hold,
            // so it fails the decode rather than resolving to a hold.
            let passage = try container.decode(Passage.self, forKey: .passage)
            self = Breath(kind: kind, through: passage)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(passage, forKey: .passage)
    }
}

/// Written out because the associated passage stops the compiler synthesising
/// it. This type is the set of things the app can say, so the tests that ask
/// whether everything sayable has been said need to enumerate it.
extension Breath: CaseIterable {
    public static var allCases: [Breath] {
        Passage.allCases.flatMap { [Breath.inhale(through: $0), .exhale(through: $0)] }
            + [.holdIn, .holdOut]
    }
}
