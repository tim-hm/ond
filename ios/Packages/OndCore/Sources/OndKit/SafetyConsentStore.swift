import Foundation
import Observation

/// Whether this person has agreed to the safety terms, and the record of it.
/// Written once, never edited — no undo, no clear — and it keeps the words, not
/// a flag: `needsConsent` going false must be answerable with what and when,
/// months later. In `UserDefaults` because the record belongs to the install —
/// a `Profile` sync would restore consent onto a device that never asked.
@MainActor
@Observable
public final class SafetyConsentStore: PersonalStore {
    /// `SafetyNoteStore`'s key, kept for the sole purpose of deleting it: left
    /// in `UserDefaults` it names the contraindicated exercises an erased person
    /// had been reading about. Swept from `erase()` rather than a launch-time
    /// migration — a permanent fixture for a one-off — so it lingers, harmlessly,
    /// on every install that never asks to be forgotten.
    private static let dismissedNotesKey = "safety.dismissedNotes"

    /// What this person agreed to, or nil if they never have.
    public private(set) var agreed: AgreedSafetyConsent?

    /// The words to put on screen, and the words `record()` will store — one
    /// source for both, so what somebody read and what they agreed to cannot
    /// drift apart.
    public let terms: SafetyConsent

    private let defaults: UserDefaults
    private let store: DefaultsJSONStore<AgreedSafetyConsent>

    /// - Parameter terms: the words to ask about. Injected so a test can raise
    ///   the version without editing the copy every screen shows.
    public init(terms: SafetyConsent = .current, defaults: UserDefaults = .standard) {
        self.terms = terms
        self.defaults = defaults
        store = DefaultsJSONStore(
            key: "safety.consent",
            what: "the consent record",
            category: "safety",
            defaults: defaults
        )
        agreed = store.load()
    }

    /// Whether this person still has to be asked. True for a fresh install and
    /// for somebody who onboarded before this screen existed: no record is the
    /// same state as never asked, not the same as agreed. Compared with `<`
    /// rather than `!=` so a TestFlight downgrade does not re-ask terms someone
    /// has already been past.
    public var needsConsent: Bool {
        guard let agreed else { return true }
        return agreed.version < terms.version
    }

    /// Records agreement to the terms as they currently read. Idempotent while
    /// `needsConsent` is false: someone stepping back and forward through
    /// onboarding must not overwrite the timestamp of the agreement that counted.
    /// - Parameter now: injected only so a test can assert on a time it chose.
    public func record(at now: Date = .now) {
        guard needsConsent else { return }

        let record = AgreedSafetyConsent(version: terms.version, agreedAt: now, text: terms.text)
        store.save(record)
        agreed = record
    }

    /// Forgets the agreement, so the terms are asked again on the next launch —
    /// the store a deletion must not miss: this holds a dated statement that a
    /// person agreed to something, and keeping it would make "delete everything"
    /// a lie. Asked again is the honest consequence: `ProfileStore.erase` puts
    /// onboarding back, and the next person on this device has agreed to nothing.
    public func erase() async {
        agreed = nil
        store.erase()
        defaults.removeObject(forKey: Self.dismissedNotesKey)
    }
}
