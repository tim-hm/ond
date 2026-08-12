import Foundation
import Observation

/// The one way a tapped mood reaches Health, and the whole of what happens to
/// it: a sample on the device it was tapped on, and nothing else.
///
/// Deliberately not a store. It holds no mood, keeps no history and answers no
/// question about one — which is what lets the app close the "is this doing
/// anything?" loop without becoming a second place somebody's feelings live.
/// The record is Health's, where the person can read it, chart it against the
/// resting rate beside it, and delete it without asking this app's permission.
/// Nothing here reaches the server, and nothing here should: a session's slug
/// and its minutes sync, and how somebody felt is not that.
///
/// `@Observable` for one reason — it is how the composition root hands the same
/// instance to the two screens that ask, before the breathing and after it. It
/// has no observable state and wants none.
///
/// There is no in-app switch governing the write, unlike the Mindful Minutes
/// one beside it. That write happens invisibly after every kept session, so it
/// needs a preference; this one happens only when somebody taps a mood, and the
/// preference that decides whether they are ever asked is
/// `SessionSettings.asksHowYouFeel`. No prompt, no tap, no write.
@MainActor
@Observable
public final class MoodRecorder {
    private let store: any HealthStore

    public init(store: any HealthStore) {
        self.store = store
    }

    /// Records `mood` as felt at `date`.
    ///
    /// Returns once the write has been attempted, which the caller before a
    /// session needs — see `HealthStore.writeMood(_:at:)`. It never reports what
    /// happened, because there is nothing useful to say: a refusal is Health's
    /// to explain, in Health, and the tap has already done its job on screen.
    public func note(_ mood: Mood, at date: Date = Date()) async {
        await store.writeMood(mood, at: date)
    }
}
