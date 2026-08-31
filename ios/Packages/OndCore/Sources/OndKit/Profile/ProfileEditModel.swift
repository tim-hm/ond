import Foundation
import Observation

/// Drives a screen that changes what somebody already told the app about
/// themselves. One model behind two screens — Settings' profile form and the
/// leaderboard's name sheet — so the display-name rule lives in one place. A
/// client that clamps differently from the server makes every sync fail
/// silently. In `OndKit`, because the app target has no test bundle.
@MainActor
@Observable
public final class ProfileEditModel {
    /// The answers as they stand on screen: the whole profile, taken from the
    /// store when this was made and written back by `save()`. One struct
    /// rather than a property per field, because `UpdateProfile` replaces the
    /// whole profile. Snapshot semantics are safe because nothing else writes
    /// the profile while one of these screens is up.
    public var draft: Profile {
        didSet { clampToServerLimits() }
    }

    /// True while the save is in flight, so the screen can refuse a second one.
    public private(set) var isSaving = false

    /// What the server said when it refused the answers; `nil` when it did not
    /// refuse. A refusal is not a failed send: an unreachable server leaves the
    /// answers stored and retried, but a refused one never becomes true. Read
    /// from the store, so a refusal arriving elsewhere cannot leave a stale
    /// verdict on this screen.
    public var rejection: String? {
        if case let .rejected(reason) = store.syncState {
            reason
        } else {
            nil
        }
    }

    private let store: ProfileStore

    public init(store: ProfileStore) {
        self.store = store
        draft = store.profile
    }

    /// Adds or removes a goal, keeping the order they were picked in — the order
    /// the coach's prompt reads them back in, so it is an answer rather than a
    /// set.
    public func toggle(_ goal: TechniqueGoal) {
        if let index = draft.goals.firstIndex(of: goal) {
            draft.goals.remove(at: index)
        } else {
            draft.goals.append(goal)
        }
    }

    public func isSelected(_ goal: TechniqueGoal) -> Bool {
        draft.goals.contains(goal)
    }

    /// An empty name is always allowed — it means "take me off the boards", and
    /// clearing one must stay as easy as setting one. Anything else has to clear
    /// the server's minimum, or the save would come back `INVALID_ARGUMENT`.
    public var canSave: Bool {
        let trimmed = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSaving
            && (trimmed.isEmpty || trimmed.unicodeScalars.count >= Profile.minDisplayNameLength)
    }

    /// Saves, and reflects back whatever the server decided to store. Awaited,
    /// unlike onboarding's: a taken display name comes back suffixed and a
    /// duplicated goal comes back dropped. A server that could not be reached
    /// is not an error, because the next launch retries.
    public func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        // Trimmed here rather than as it is typed, unlike the length and the
        // control characters: a name being typed passes through "Ann " on the
        // way to "Ann Marie", and a field that ate the space would be
        // unusable. The server trims too — this is so the local copy agrees
        // with what it stores.
        draft.displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.givenName = draft.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        await store.save(draft)

        switch store.syncState {
        case .rejected:
            // The stored answers are deliberately not read back. They are the
            // ones the server refused, and putting them on screen would present
            // a profile nobody else will ever see as the one that was saved.
            break
        case .settled, .pending:
            draft = store.profile
        }
    }

    /// Narrows every free-text field to what the server accepts, so a field
    /// stops accepting input rather than failing at save. The rules are
    /// `Profile.clampedToServerLimits()`'s. Assigned once from the result:
    /// `draft` is observed, so narrowing field by field in place would re-enter
    /// here and not bottom out. One assignment re-enters exactly once.
    private func clampToServerLimits() {
        let clamped = draft.clampedToServerLimits()
        guard clamped != draft else { return }

        draft = clamped
    }
}
