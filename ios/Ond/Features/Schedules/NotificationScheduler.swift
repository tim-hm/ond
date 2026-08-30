import OndKit
import os
import UserNotifications

/// The real `ScheduleNotifying`: schedules land as repeating local
/// notifications, one request per schedule per weekday — a calendar trigger
/// with a `weekday` component is the only way iOS repeats "Mondays at 08:00".
/// iOS caps pending requests at 64 (nine every-day schedules); `sync`
/// replaces wholesale, so only that many real appointments can hit the cap.
struct NotificationScheduler: ScheduleNotifying {
    /// Marks every request this app's schedules own, so a resync can clear
    /// them without touching any other notification the app may one day send.
    private static let prefix = "schedule-"

    private static let logger = Logger(category: "schedules")

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            // Re-asking after a decision is a no-op that answers the standing
            // permission, so this is safe to call on every schedule creation.
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if !granted {
                Self.logger.notice("notifications not authorised, so no reminder can fire")
            }
            return granted
        } catch {
            Self.logger.notice(
                "asking for notifications failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func sync(_ schedules: [Schedule]) async {
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        )

        var accepted = 0
        for schedule in schedules where schedule.isEnabled {
            var refusal: (any Error)?
            for day in schedule.weekdays {
                do {
                    try await center.add(request(for: schedule, on: day))
                    accepted += 1
                } catch {
                    refusal = error
                }
            }

            // One line per schedule rather than one per weekday, because a
            // schedule's days fail together and seven lines would say one
            // thing. The requests this sync replaced were removed above, so
            // what the line reports is a reminder that was firing until now.
            if let refusal {
                Self.logger.notice(
                    "failed to schedule a reminder for \(schedule.id.uuidString, privacy: .public): \(refusal.localizedDescription, privacy: .public)"
                )
            }
        }

        // `add` does not throw at the 64-pending-request cap — iOS accepts the
        // request and silently keeps the 64 soonest to fire — so the dominant
        // way a reminder gets dropped leaves no error to catch. Counting what
        // survived is the only way to see it happen.
        let kept = await center.pendingNotificationRequests()
            .count { $0.identifier.hasPrefix(Self.prefix) }
        if kept < accepted {
            Self.logger.notice(
                "iOS kept \(kept) of \(accepted) reminder notifications; the rest fell past the pending-request cap"
            )
        }
    }

    private func request(for schedule: Schedule, on day: Weekday) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = schedule.techniqueName
        content.body = "This is your \(schedule.timeLabel) practice reminder."
        content.sound = .default
        // Self-describing, so the tap opens the exercise the reminder named
        // rather than whichever exercise the schedule points at by then. See
        // `NotificationPayload`.
        content.userInfo = NotificationPayload(techniqueSlug: schedule.techniqueSlug).userInfo

        var components = DateComponents()
        components.weekday = day.rawValue
        components.hour = schedule.hour
        components.minute = schedule.minute

        return UNNotificationRequest(
            identifier: "\(Self.prefix)\(schedule.id.uuidString)-\(day.rawValue)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
    }
}
