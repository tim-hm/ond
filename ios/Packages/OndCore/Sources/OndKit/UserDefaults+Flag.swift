import Foundation

public extension UserDefaults {
    /// The switch stored under `key`, or `fallback` where nobody has ever
    /// touched it.
    ///
    /// The reason this exists rather than `bool(forKey:)`: that method answers
    /// false for a key nobody has written, which is indistinguishable from a
    /// stored false and is the wrong answer for every preference that ships
    /// *on*. Three of them do, and each used to spell the workaround its own
    /// way — one of which read the stored value with a cast and one with a
    /// coercion, so they did not even agree on what a non-Bool under the key
    /// meant.
    func flag(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }
}
