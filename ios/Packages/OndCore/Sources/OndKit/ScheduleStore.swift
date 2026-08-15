import Foundation
import Observation

/// Whatever turns the schedule list into pending notifications.
///
/// A seam for the same reason `SessionCueing` is one: `UNUserNotificationCenter`
/// is an app-target concern that cannot run on the host under test, and the
/// store's real logic — what the list is and when it changed — does not need
/// it. The app hands in the real scheduler; tests hand in a spy.
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

/// The schedules, and the one place they change.
///
/// `UserDefaults` rather than a file store: this is configuration in the same
/// sense as `SessionSettings` — a handful of values, read at launch, written
/// on edit — not history that grows. Every mutation re-syncs the notification
/// center from the full list, so what iOS will fire and what this list says
/// can only drift between a change and the async resync completing.
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
    /// it, so the prompt lands on the screen where somebody set the reminder
    /// dial rather than after they have finished with it.
    ///
    /// Additive: [`add(_:)`] still asks for itself, and iOS shows the alert at
    /// most once per install, so a schedule made without this having run is
    /// unaffected and one made after it resolves quietly.
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

    /// Reshapes the dial-owned reminder to what the profile's dial now says.
    ///
    /// The dial governs exactly one schedule — the one marked `fromDial` — and
    /// only its frequency. A time or technique the person edited onto it
    /// survives a frequency change; every schedule they made themselves is
    /// untouched, whatever the dial does.
    ///
    /// `never` removes the dial's reminder, which is the promise the label
    /// makes. The other two positions re-enable a paused one as they reshape
    /// it: moving the dial is an explicit ask to be reminded at that cadence,
    /// and honouring the frequency while staying silent would be the inert
    /// dial this exists to replace.
    ///
    /// - Parameter technique: what a *newly created* reminder opens with, when
    ///   the dial moves off `never` and no dial-owned schedule survives to
    ///   reshape — the person deleted it, or onboarding never made one. Nil
    ///   when the caller has no catalogue to offer; an existing schedule is
    ///   still reshaped, and only the create is skipped.
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

    /// Forgets the appointments, and unregisters the notifications they had
    /// already placed with iOS.
    ///
    /// The list itself is personal data and not merely configuration: a
    /// technique, an hour, a minute and a set of weekdays is a record of
    /// somebody's routine and of when they are at home.
    ///
    /// The pending requests are the half that would be *seen*. They live in the
    /// notification centre rather than in this app, they survive it being
    /// killed, and they fire on the lock screen naming the exercise — so a
    /// deletion that dropped the list alone would have the erased account
    /// announcing itself the next morning, on a schedule, to somebody who was
    /// told their practice was gone from this iPhone.
    ///
    /// Awaited rather than sent off in a `Task` like every other mutation here:
    /// the rest of this class is answering somebody editing a list who will not
    /// notice the resync, and this one is the last thing that happens before an
    /// erasure claims to be complete. `sync` takes the whole list by design, so
    /// an empty one removes every request this app owns and adds none.
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
