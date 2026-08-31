import Foundation
import Observation

/// A caution that can belong either to an exercise or to the moment framing
/// it for a particular context.
public struct SessionWarning: Sendable, Equatable {
    /// Stable persistence key. Moments namespace their occasion slug so they
    /// cannot accidentally inherit a silence for an exercise with the same key.
    public let key: String
    /// What the warning screen names after "Before".
    public let title: String
    public let text: String

    public init(key: String, title: String, text: String) {
        self.key = key
        self.title = title
        self.text = text
    }
}

/// One session caution as somebody accepted it. The words are kept, not a
/// flag: "accepted" is worth nothing unless it can say what was on the
/// screen, and a silence covers only those words — a rewritten note is a
/// warning nobody has accepted yet.
public struct AcceptedTechniqueWarning: Codable, Sendable, Equatable {
    /// When the person accepted. Never back-filled.
    public let acceptedAt: Date
    /// The warning text as it read at that moment.
    public let text: String
    /// Whether they also asked not to be shown it again.
    public let silenced: Bool

    public init(acceptedAt: Date, text: String, silenced: Bool) {
        self.acceptedAt = acceptedAt
        self.text = text
        self.silenced = silenced
    }
}

/// Which exercise or moment warnings this person has accepted, and whether
/// they asked for them not to come back. Distinct from `SafetyConsentStore`,
/// whose agreement is to breathwork at all: silencing one session's hazard
/// must never touch that consent. Keyed by a stable domain key, so a
/// catalogue re-fetch that reissues ids does not un-silence anything.
@MainActor
@Observable
public final class TechniqueWarningStore: PersonalStore {
    /// What this person has accepted, by exercise or moment key.
    public private(set) var accepted: [String: AcceptedTechniqueWarning]

    private let store: DefaultsJSONStore<[String: AcceptedTechniqueWarning]>

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsJSONStore(
            key: "safety.techniqueWarnings",
            what: "the accepted technique warnings",
            category: "safety",
            defaults: defaults
        )
        accepted = store.load() ?? [:]
    }

    /// Whether starting a session should put its warning on screen first.
    ///
    /// True whenever the session carries a note and no *silence* covers it —
    /// an acceptance without the tick was for that session, not this one — and
    /// true again the moment the note is reworded, whatever was silenced.
    public func needsWarning(for warning: SessionWarning?) -> Bool {
        guard let warning else { return false }
        guard let record = accepted[warning.key], record.silenced else { return true }
        return record.text != warning.text
    }

    /// Records that the warning was read and accepted, replacing whatever its
    /// key held: un-ticking the box must be able to lift an old silence.
    /// `now` is injected only so a test can assert on a time it chose.
    public func accept(_ warning: SessionWarning, silenced: Bool, at now: Date = .now) {
        accepted[warning.key] = AcceptedTechniqueWarning(
            acceptedAt: now,
            text: warning.text,
            silenced: silenced
        )
        store.save(accepted)
    }

    /// Compatibility entry point for callers working directly with an
    /// exercise. Moment launches use their own warning value instead.
    public func needsWarning(for technique: Technique) -> Bool {
        needsWarning(for: technique.sessionWarning)
    }

    /// Compatibility entry point for a direct exercise warning.
    public func accept(_ technique: Technique, silenced: Bool, at now: Date = .now) {
        guard let warning = technique.sessionWarning else { return }
        accept(warning, silenced: silenced, at: now)
    }

    /// Forgets every acceptance, so each warning is shown again — the same
    /// honest consequence `SafetyConsentStore.erase` lands on: the next person
    /// on this device has accepted nothing.
    public func erase() async {
        accepted = [:]
        store.erase()
    }
}

public extension Technique {
    /// This exercise's own caution in the shape a session warning screen needs.
    var sessionWarning: SessionWarning? {
        safetyNote.map { SessionWarning(key: slug.rawValue, title: name, text: $0) }
    }
}
