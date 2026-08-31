import Foundation
import os

/// The profile as this device holds it, and the one thing that decides whether
/// onboarding runs. Local first, server second: the answers reach
/// `UserDefaults` before the RPC, the completion flag is set either way, and
/// anything unsent is retried next launch. `UserDefaults`, not the Keychain,
/// because a reinstall may lose answers; `restoredProfile()` reads them back.
@MainActor
@Observable
public final class ProfileStore: PersonalStore {
    private static let logger = Logger(category: "profile")

    private static let completedKey = "profile.onboardingCompleted"
    private static let pendingKey = "profile.pendingSync"

    /// What this person answered, or `.unanswered` before they have.
    ///
    /// Each of these three writes through on assignment, the same way
    /// `SessionSettings` does: the property is the only thing a mutation has to
    /// remember, so the value in memory and the value on disk cannot drift.
    public private(set) var profile: Profile {
        didSet { persist(profile) }
    }

    /// Whether the stepper has been through to the end. The only gate on
    /// showing it, and set locally, so a person is never asked twice because a
    /// request failed.
    public private(set) var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Self.completedKey) }
    }

    /// How far the stored answers have got towards the server.
    ///
    /// One enum rather than a flag beside a reason, for the usual cause: the two
    /// would admit "outstanding and already refused", which is the state this
    /// exists to make unsayable.
    public enum SyncState: Sendable, Equatable {
        /// The server holds what this device holds.
        case settled
        /// Waiting for a chance to send. Every launch retries.
        case pending
        /// The server refused these answers and would refuse them again, so
        /// nothing retries. Carries its reason, for the screen that asked.
        case rejected(String)
    }

    /// Only `pending` is written to disk, as the flag it has always been: a
    /// relaunch reads a refusal back as `settled` because the whole point of
    /// the case is that no later attempt is made, and a stored one would keep
    /// answering a question with no request behind it.
    public private(set) var syncState: SyncState {
        didSet { defaults.set(syncState == .pending, forKey: Self.pendingKey) }
    }

    /// Whether the stored answers are still waiting to reach the server.
    ///
    /// Not public: no screen asks this, only the guard below and the tests that
    /// pin it, and a second public name for a derived fact is a second thing to
    /// keep in step.
    var isPendingSync: Bool {
        syncState == .pending
    }

    private let profiles: any ProfileSyncing
    private let defaults: UserDefaults
    private let store: DefaultsJSONStore<Profile>

    public init(profiles: any ProfileSyncing, defaults: UserDefaults = .standard) {
        self.profiles = profiles
        self.defaults = defaults
        store = DefaultsJSONStore(
            key: "profile.answers",
            what: "the profile answers",
            category: "profile",
            defaults: defaults
        )

        // Assigning in an initialiser does not run `didSet`, which is what keeps
        // this from writing back the values it just read.
        //
        // Unreadable answers read as unanswered — always a valid profile, and
        // the questions are one screen away.
        profile = store.load() ?? .unanswered
        hasCompletedOnboarding = defaults.bool(forKey: Self.completedKey)
        syncState = defaults.bool(forKey: Self.pendingKey) ? .pending : .settled
    }

    /// Records the answers and closes onboarding, whether or not the network is
    /// there. Synchronous on purpose: awaiting the upload would put a request
    /// timeout between the last question and the first breath.
    public func complete(with profile: Profile) {
        self.profile = profile
        syncState = .pending
        hasCompletedOnboarding = true
    }

    /// The answers the server holds, when they are worth adopting.
    ///
    /// The reinstall case: the identity survives in the Keychain while these
    /// answers do not, so a person the app has met arrives looking new. Nil
    /// covers everything that is not a restore, including any failure at all.
    public func restoredProfile() async -> Profile? {
        guard !hasCompletedOnboarding else { return nil }

        do {
            let stored = try await profiles.fetch()
            return stored.hasAnswers ? stored : nil
        } catch {
            Self.logger
                .notice("profile restore deferred: \(error.diagnostic, privacy: .public)")
            return nil
        }
    }

    /// Takes the server's answers as this device's own and closes onboarding.
    ///
    /// Nothing is left pending: what is being stored *came from* the server, and
    /// sending it back would be a write nobody made — which is the asymmetry
    /// that made a reinstall overwrite a good profile in the first place.
    public func adopt(_ profile: Profile) {
        self.profile = profile
        syncState = .settled
        hasCompletedOnboarding = true
    }

    /// Stores a change made after onboarding — the leaderboard name, the birth
    /// year band — and pushes it if it can. Unlike `complete(with:)` this
    /// awaits the upload, because the server may change a name under the
    /// person. An unreachable server is not an error; a refused one is, and
    /// `syncState` is how the screen tells the two apart.
    public func save(_ profile: Profile) async {
        self.profile = profile
        syncState = .pending
        await syncIfNeeded()
    }

    /// Pushes anything the server has not seen. Safe to call on every launch
    /// and after every change: it returns immediately when nothing is
    /// outstanding, and a failure it can only wait out leaves the answers
    /// outstanding rather than surfacing an error.
    public func syncIfNeeded() async {
        guard isPendingSync else { return }

        do {
            // The stored profile is replaced by what came back, so a value the
            // server normalised does not leave this device disagreeing with it
            // and re-syncing forever.
            profile = try await profiles.update(profile)
            syncState = .settled
        } catch let ProfileRepositoryError.rejected(reason) {
            // Cleared rather than left outstanding: the server has judged the
            // answers and not the connection, so every later attempt is the
            // same doomed request on every cold launch for the life of the
            // install. The reason survives for whoever asked for the change.
            Self.logger.notice("profile refused: \(reason, privacy: .public)")
            syncState = .rejected(reason)
        } catch {
            Self.logger
                .notice("profile sync deferred: \(error.diagnostic, privacy: .public)")
        }
    }

    /// Forgets the answers, and that they were ever given. Onboarding comes
    /// back with them, which is the honest consequence: the answers have just
    /// been erased on both sides. The keys are removed rather than left holding
    /// the written values, because an empty profile in `UserDefaults` is still
    /// a record that somebody was here.
    public func erase() async {
        profile = .unanswered
        syncState = .settled
        hasCompletedOnboarding = false

        store.erase()
        defaults.removeObject(forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.pendingKey)
    }

    private func persist(_ profile: Profile) {
        store.save(profile)
    }
}
