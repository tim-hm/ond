import Foundation
import Observation

/// Whatever turns the schedule list into pending notifications. A seam for
/// `SessionCueing`'s reason: `UNUserNotificationCenter` is an app-target
/// concern that cannot run on the host under test, and the store's real logic
/// does not need it. The app hands in the real scheduler; tests hand in a spy.
public protocol ScheduleNotifying: Sendable {
    /// Asks the person for notification permission if it has never been asked.
    /// Answers whether notifications are allowed; a refusal does not stop
    /// schedules being kept, only heard.
    func requestAuthorization() async -> Bool
    /// Replaces every pending schedule notification with `schedules`' current
    /// truth. Called with the whole list, not a delta — replacing wholesale is
    /// idempotent, and a missed delta cannot strand a stale trigger.
    func sync(_ schedules: [Schedule]) async
}

/// The schedules, and the one place they change. `UserDefaults` rather than a
/// file store: configuration like `SessionSettings`, not history that grows.
/// Every mutation re-syncs the notification center from the full list, so what
/// iOS will fire and what this list says can only drift while a resync is in
/// flight.
@MainActor
@Observable
public final class ScheduleStore: PersonalStore {
    public private(set) var schedules: [Schedule]

    private let store: DefaultsJSONStore<[Schedule]>
    private let notifier: any ScheduleNotifying

    public init(notifier: any ScheduleNotifying, defaults: UserDefaults = .standard) {
        self.notifier = notifier
        store = DefaultsJSONStore(
            key: "schedules.list",
            what: "the schedule list",
            category: "schedules",
            defaults: defaults
        )
        schedules = store.load() ?? []
    }

    /// Asks for notification permission ahead of the schedule that will need
    /// it, so the prompt lands where somebody set the reminder dial. Additive:
    /// [`add(_:)`] still asks for itself, and iOS shows the alert at most once
    /// per install, so running or skipping this changes nothing later.
    public func requestNotificationAuthorization() async {
        _ = await notifier.requestAuthorization()
    }

    /// Adds a schedule and asks for notification permission in the same
    /// breath — the first schedule is the moment a reminder set up anywhere
    /// but onboarding comes due.
    public func add(_ schedule: Schedule) {
        schedules.append(schedule)
        persist()
        Task {
            _ = await notifier.requestAuthorization()
            await notifier.sync(schedules)
        }
    }

    /// Replaces the schedule with `schedule.id`, if it still exists.
    public func update(_ schedule: Schedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
        persistAndResync()
    }

    public func remove(_ schedule: Schedule) {
        schedules.removeAll { $0.id == schedule.id }
        persistAndResync()
    }

    /// Flips one schedule without opening the editor — the row's toggle.
    public func setEnabled(_ isEnabled: Bool, for schedule: Schedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index].isEnabled = isEnabled
        persistAndResync()
    }

    /// Reshapes the dial-owned reminder — the one `fromDial` schedule, and only
    /// its frequency: an edited time or technique survives; self-made schedules
    /// are untouched. `never` removes it; the other positions re-enable a paused one.
    /// - Parameter technique: opens a newly created reminder when none survives
    ///   to reshape. Nil skips only the create; an existing one is still reshaped.
    public func applyDial(_ intensity: ReminderIntensity, technique: Technique?) {
        guard let days = ReminderSeed.days(for: intensity) else {
            if let owned = schedules.first(where: \.fromDial) {
                remove(owned)
            }
            return
        }

        if let index = schedules.firstIndex(where: \.fromDial) {
            schedules[index].weekdays = days
            schedules[index].isEnabled = true
            persistAndResync()
            return
        }

        guard let technique,
              let seeded = ReminderSeed.schedule(for: intensity, technique: technique)
        else { return }

        // `add` rather than a bare append: the dial moving off `never` is the
        // moment the onboarding promise about notification permission comes
        // due, exactly as it is when the seed first runs.
        add(seeded)
    }

    /// Forgets the appointments and unregisters the notifications already placed
    /// with iOS. The pending requests outlive this app and fire on the lock
    /// screen naming the exercise, so dropping the list alone would have the
    /// erased account announcing itself the next morning. Awaited, unlike every
    /// other mutation's resync: the last thing before an erasure claims complete.
    public func erase() async {
        schedules = []
        store.erase()

        await notifier.sync(schedules)
    }

    private func persistAndResync() {
        persist()
        Task { await notifier.sync(schedules) }
    }

    private func persist() {
        store.save(schedules)
    }
}
