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

/// What the breath does in one phase, and — where air is moving — where it goes.
///
/// The passage rides on the movement rather than sitting beside it, so a hold
/// through the left nostril cannot be written down: air that is not moving goes
/// nowhere, and the two hold cases have no passage to carry. That is the same
/// shape `ond.v1.DraftPhase`'s oneof has, for the same reason — and it makes
/// decoding a served `Phase` total rather than a silent drop of a field that
/// should never have been set.
///
/// Four cases mirroring `PhaseKind` rather than three with a lungs state,
/// because `kind` is what every cue, haptic and colour switches on and a second
/// vocabulary for the same distinction would be one more thing to keep in step.
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

    /// The breath a `kind` and a passage describe, with the passage consulted
    /// only where there is somewhere to put it.
    ///
    /// The one way onto this type from the pair the wire and the database carry
    /// separately. Total in both arguments: a hold arriving with a passage
    /// resolves to a hold, because the case it maps to has no room for one.
    public init(kind: PhaseKind, through passage: Passage) {
        switch kind {
        case .inhale: self = .inhale(through: passage)
        case .holdIn: self = .holdIn
        case .exhale: self = .exhale(through: passage)
        case .holdOut: self = .holdOut
        }
    }
}

/// Written out rather than synthesised, because the associated passage stops
/// the compiler doing it.
///
/// Worth having as a list at all because this type is a vocabulary as much as a
/// model: it is the set of things the app can say, so the tests that ask whether
/// everything sayable has been said need to enumerate it.
extension Breath: CaseIterable {
    public static var allCases: [Breath] {
        Passage.allCases.flatMap { [Breath.inhale(through: $0), .exhale(through: $0)] }
            + [.holdIn, .holdOut]
    }
}
