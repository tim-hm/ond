import Foundation
import Observation

/// The one way a tapped mood reaches Health: a sample on the device it was
/// tapped on. It stores no mood and sends nothing to the server. Its own type
/// because the first mood is tapped before a session exists. `@Observable`
/// only so the composition root hands one instance to both session screens.
/// `SessionSettings.asksHowYouFeel` decides whether anyone is asked at all.
@MainActor
@Observable
public final class MoodRecorder {
    private let store: any HealthStore

    /// Whether Health has answered that the write grant is decided.
    private var isSettled = false

    public init(store: any HealthStore) {
        self.store = store
    }

    /// Records `mood` as felt at `date`. It returns once the write has been
    /// attempted, which the caller before a session needs, and reports
    /// nothing: a refusal is Health's to explain. See
    /// `HealthStore.writeMood(_:at:)`.
    public func note(_ mood: Mood, at date: Date = Date()) async {
        await store.writeMood(mood, at: date)
    }

    /// Whether the next `note(_:at:)` can still raise Health's own sheet — see
    /// `HealthStore.writeMoodMayPrompt()`. The countdown holds itself only for
    /// a write that can put a modal over it. A settled answer is kept, since a
    /// grant never returns to undecided; an undecided one is not, because the
    /// write that follows is about to settle it.
    public func writeMayPrompt() async -> Bool {
        guard !isSettled else { return false }

        let mayPrompt = await store.writeMoodMayPrompt()
        isSettled = !mayPrompt
        return mayPrompt
    }
}
