import UserNotifications

/// Tells somebody who pocketed a silent phone that their session stopped.
/// A pause nobody is told about is the actual fault — they breathe to nothing.
/// A local notification is the only channel left: the app has no runtime and
/// a locked screen withholds haptics. In `OndKit` because `SessionActivity`
/// withdraws it on a lock-screen end, which never returns through a scene phase.
public enum SessionPausedNotice {
    /// One identifier for the one notice there can be, so `withdraw()` takes
    /// back exactly this and never a reminder a schedule placed.
    private static let identifier = "session-paused"

    /// How long a departure has to last before it is worth saying anything:
    /// iOS sends `.background` for a two-second glance at another app as
    /// readily as for a phone going into a pocket. A return inside the window
    /// withdraws the request before it ever fires.
    private static let quietPeriod: TimeInterval = 15

    /// Asks for the notice, if the person is still away when the window closes.
    /// Authorization is used, never requested, here: the prompt would surface
    /// on their return to ask about a thing that has already happened.
    /// Unauthorized, `add` is a no-op and the pause stays quiet.
    public static func post() {
        let content = UNMutableNotificationContent()
        content.title = "Your session is paused"
        // Three sentences, each doing one job: the why, the way back, and the
        // way round — the wrist is the one surface a dark screen does not stop,
        // and this is the moment somebody is holding the problem it solves.
        content.body =
            "With sound off, önd can't reach a locked screen. Open it to carry on where you left off. Your watch can run one with the screen dark."
        // Sound, despite this being somebody who chose a silent practice,
        // because it is the only part of the notice that reaches a pocket: the
        // system plays a notification's alert itself, so it still lands as a
        // vibration on a phone switched to silent, where the app's own haptics
        // never would.
        content.sound = .default
        // No `NotificationPayload`, deliberately. The tap should return to the
        // session already on screen — which resuming on `.active` does — rather
        // than route to the exercise and open a second one over it.

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: quietPeriod,
                    repeats: false
                )
            )
        )
    }

    /// Takes the notice back, whether or not one was ever posted.
    ///
    /// Both lists, because a return can beat the quiet period or lose to it, and
    /// a delivered "your session is paused" outliving the pause is the same lie
    /// in the other direction.
    public static func withdraw() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
