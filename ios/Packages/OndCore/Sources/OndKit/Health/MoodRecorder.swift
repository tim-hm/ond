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
}
