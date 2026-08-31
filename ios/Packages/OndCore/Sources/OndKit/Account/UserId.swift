import Foundation

/// The person this install files its work under. A type because the watch is
/// never allowed to mint one, and because a hand-over carries it beside an
/// order id of the same shape. ``StringIdentifier`` cannot serve it: bare-value
/// encoding is free only for a `String` raw value, so `Codable` is written out
/// here, and a synthesized one would rewrite every stored id as an object.
public struct UserId: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Reads the canonical form the Keychain, the hand-over and the server all
    /// carry the id as. Nil where the text is not a UUID.
    public init?(uuidString: String) {
        guard let parsed = UUID(uuidString: uuidString) else { return nil }

        rawValue = parsed
    }

    /// The one string form. Every store writes this and reads it back, so the
    /// spelling lives here rather than at each boundary.
    public var uuidString: String {
        rawValue.uuidString
    }

    public var description: String {
        uuidString
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
