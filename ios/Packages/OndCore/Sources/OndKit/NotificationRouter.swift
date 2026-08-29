import Foundation
import Observation

/// The road from a tapped notification to the screen it opens. State, not a
/// call: a tap from terminated reaches the delegate while the scene is still
/// being composed, so a delegate calling a view would drop the tap that
/// launched the app. The chrome takes the held request once it exists, so a
/// cold launch and a warm one follow one path.
@MainActor
@Observable
public final class NotificationRouter {
    /// What a tap asked for and nothing has opened yet.
    public private(set) var pending: NotificationPayload?

    public init() {}

    /// Records a tap. The most recent one wins: two reminders tapped before
    /// either opened is one person changing their mind, not two exercises.
    public func request(_ payload: NotificationPayload) {
        pending = payload
    }

    /// Takes the request, leaving nothing behind.
    ///
    /// Consuming rather than reading, so a route is followed once — a session
    /// screen dismissed must not be reopened by the request that opened it, and
    /// a request that resolves to no exercise must not be retried on every pass.
    public func take() -> NotificationPayload? {
        defer { pending = nil }
        return pending
    }
}
