import OndKit
import UserNotifications

/// Turns a tapped notification into a request on the router, and does nothing
/// else. Thin on purpose, and untested for the same reason: it is the one
/// object in this feature no host test can construct. The thinking lives in
/// `OndKit` — what the notification carries is `NotificationPayload`'s, and
/// where the tap goes is `NotificationDestination`'s.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let router: NotificationRouter

    /// Builds the delegate, hands it to the notification centre, and returns
    /// it to be held: `UNUserNotificationCenter.delegate` is weak, and a
    /// delegate nobody retains is a tap that lands nowhere. Call from the
    /// composition root's `init`, not a `.task` — a tap from terminated is
    /// delivered as the app launches, and a late delegate misses it.
    @MainActor
    static func installed(routing router: NotificationRouter) -> NotificationDelegate {
        let delegate = NotificationDelegate(router: router)
        UNUserNotificationCenter.current().delegate = delegate
        return delegate
    }

    private init(router: NotificationRouter) {
        self.router = router
        super.init()
    }

    /// A tap on the notification itself, rather than a swipe away or one of the
    /// action buttons this app does not offer.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let payload = NotificationPayload(
                  userInfo: response.notification.request.content.userInfo
              )
        else { return }

        await router.request(payload)
    }
}
