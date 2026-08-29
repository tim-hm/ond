import Foundation

public extension UserDefaults {
    /// The switch stored under `key`, or `fallback` where nobody has ever
    /// touched it. Exists because `bool(forKey:)` answers false for a key
    /// nobody has written — indistinguishable from a stored false, and the
    /// wrong answer for every preference that ships *on*.
    func flag(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }
}
