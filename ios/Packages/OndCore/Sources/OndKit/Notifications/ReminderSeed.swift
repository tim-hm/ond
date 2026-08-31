import Foundation

/// Turns the reminder dial into the standing appointment it promises: an
/// ordinary `Schedule` in the ordinary list, so the person can retime,
/// retarget, or delete it in Settings. The dial stays live afterwards — moving
/// it reshapes this one schedule through `ScheduleStore.applyDial`, marked out
/// by `Schedule.fromDial`. Pure, so every rule is testable without a store.
public enum ReminderSeed {
    /// What "now and then" means: three days, spread across the week, with a
    /// gap after each one. Every other day would drift into every day the
    /// moment somebody adds a fourth, and consecutive days would make two
    /// missed mornings look like a broken habit — which is the pressure the
    /// gentle setting exists to avoid.
    public static let gentleDays: Set<Weekday> = [.monday, .wednesday, .friday]

    /// The hour a goal suits — somewhere inside each stretch, not at the edge
    /// where it starts. `reset` has no band of its own, and lands in the
    /// afternoon dip that is the usual reason to want one.
    public static func hour(for goal: TechniqueGoal) -> Int {
        switch goal {
        case .energy: 7
        case .focus: 12
        case .reset: 15
        case .calm: 18
        case .sleep: 21
        }
    }

    /// The days each dial position asks for, or nil where it asks for none.
    ///
    /// The one statement of what the dial's words mean in days, shared by the
    /// onboarding seed and `ScheduleStore.applyDial` so "now and then" cannot
    /// mean three days here and four somewhere else.
    public static func days(for intensity: ReminderIntensity) -> Set<Weekday>? {
        switch intensity {
        case .never: nil
        case .gentle: gentleDays
        case .daily: Set(Weekday.allCases)
        }
    }

    /// The schedule a dial setting asks for, or nil where it asks for nothing.
    /// Nil for `never` is the whole privacy promise on this path: no schedule is
    /// created, so `ScheduleStore.add` — the only home of the notification
    /// permission prompt — is never called.
    /// - Parameter technique: what the reminder opens with, and what decides the hour.
    public static func schedule(
        for intensity: ReminderIntensity,
        technique: Technique
    ) -> Schedule? {
        guard let days = days(for: intensity) else { return nil }

        return Schedule(
            techniqueSlug: technique.slug,
            techniqueName: technique.name,
            hour: hour(for: technique.goal),
            minute: 0,
            weekdays: days,
            fromDial: true
        )
    }
}
