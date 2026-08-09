import Foundation
import os

/// One JSON blob under one `UserDefaults` key — the defaults-backed twin of
/// `JSONFileStore`, for a store whose whole state is a value read at launch and
/// written on edit.
///
/// Exists so the failure semantics `ScheduleStore` argued for are what every
/// adopter inherits rather than what each hand-rolls: a payload that stops
/// decoding is logged and preserved instead of silently dropped, an encode
/// failure is logged instead of swallowed, and `erase()` removes the preserved
/// copy along with the live one — which makes that coupling structural instead
/// of a second key every store's erasure has to hand-remember.
struct DefaultsJSONStore<Value: Codable> {
    private let key: String

    /// Where a payload that stopped decoding is copied, so the next save —
    /// which rewrites `key` from the now-defaulted value — cannot destroy the
    /// only record of what was there. Copied rather than moved: left under
    /// `key`, the payload comes back by itself on the first launch of a version
    /// that can decode it, as long as no save overwrites it first, which is
    /// exactly the window the copy exists to outlive. Nothing reads it back
    /// yet; it exists so a post-mortem (or a later version whose decoder can)
    /// still finds the data.
    private let unreadableKey: String

    /// Names the value in log lines — "the schedule list", "the profile
    /// answers" — so the message reads as the owning store's.
    private let what: String

    private let defaults: UserDefaults
    private let logger: Logger

    /// ISO-8601 dates unconditionally, matching `JSONFileStore`: the one
    /// payload with a date (the consent record) has to be legible to whoever
    /// reads it back, and a per-store strategy would be a mismatched
    /// encoder/decoder pair waiting to make every relaunch a decode failure.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// - Parameters:
    ///   - key: where the blob lives. The preserved copy lives beside it at
    ///     `<key>.unreadable`.
    ///   - what: the value as a log line should name it.
    ///   - category: the owning store's logger category, so the failure logs
    ///     beside that store's other lines.
    init(key: String, what: String, category: String, defaults: UserDefaults) {
        self.key = key
        unreadableKey = key + ".unreadable"
        self.what = what
        self.defaults = defaults
        logger = Logger(category: category)
    }

    /// The stored value, or nil where nothing is stored or the payload stopped
    /// decoding. Nil rather than a default, because every adopter's empty state
    /// is its own — an empty list, `.unanswered`, no record at all — and this
    /// type has no business choosing one.
    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            defaults.set(data, forKey: unreadableKey)
            logger.notice(
                "failed to decode \(what, privacy: .public), keeping a copy aside: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    func save(_ value: Value) {
        do {
            try defaults.set(encoder.encode(value), forKey: key)
        } catch {
            // The edit already happened in the owner's memory; what is lost is
            // the copy that survives a relaunch, and this line is its only
            // record.
            logger.notice(
                "failed to encode \(what, privacy: .public), keeping the last saved one: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Removes the value and the preserved unreadable copy in the same breath:
    /// the copy is the same data in an older encoding, and an erasure that kept
    /// it would not be one.
    func erase() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: unreadableKey)
    }
}
