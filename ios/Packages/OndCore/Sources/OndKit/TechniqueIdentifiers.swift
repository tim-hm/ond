import Foundation

/// The conformances every identifier below shares. `RawRepresentable` over
/// `String` is what makes them encode as bare strings: the standard library's
/// conformance beats the memberwise one the compiler would otherwise
/// synthesize, so a slug in a stored `SessionRecord` stays the string it has
/// always been, and files already written to a device still read.
public typealias IdentifierConformances = Codable & CodingKeyRepresentable
    & CustomStringConvertible & ExpressibleByStringLiteral & Hashable
    & RawRepresentable & Sendable

/// A string literal is admitted; a `String` a caller happens to hold is not,
/// which is the transposition these types refuse. `CodingKeyRepresentable` is
/// load-bearing: a `Dictionary` encodes as a JSON object only for a `String`,
/// an `Int`, or one of these, so without it every dialled override would be
/// rewritten as an array and read back as nothing.
public protocol StringIdentifier: IdentifierConformances where RawValue == String {
    init(rawValue: String)
}

public extension StringIdentifier {
    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    var description: String {
        rawValue
    }

    var codingKey: any CodingKey {
        IdentifierCodingKey(stringValue: rawValue)
    }

    init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}

/// The key an identifier presents itself as when it is a dictionary's key.
/// Never an integer: these are slugs, and an identifier that answered an
/// integer index would let a stored object decode as an array.
private struct IdentifierCodingKey: CodingKey {
    let stringValue: String

    var intValue: Int? {
        nil
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

/// A catalogue exercise's stable key: what this app pins artwork and haptic
/// patterns to, and what a recorded session names. A type rather than a
/// `String` because `Technique` carries this and a ``TechniqueId`` side by
/// side. Nothing validates the spelling — the server owns the bound, and every
/// slug this app holds came from it.
public struct TechniqueSlug: StringIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// An occasion's own stable key, in the namespace beside the technique slug it
/// prescribes: a `Prescription` carries one of each.
public struct OccasionSlug: StringIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The server's row id for an exercise, which only the authoring calls send.
///
/// It replaces `TechniqueId`, whose whole job was to stop a slug reaching
/// an edit — a mistake that compiled and surfaced as a server `NOT_FOUND`. The
/// guard is now the type rather than a constructor nobody has to use.
public struct TechniqueId: StringIdentifier {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
