import Foundation

/// Turns the reminder dial into the standing appointment it promises.
///
/// What it makes is an ordinary `Schedule` in the ordinary list, so the first
/// thing a person can do with it is open Settings and change the time, the
/// technique, or the days — or delete it. The dial stays live afterwards:
/// moving it in the profile reshapes this one schedule's frequency through
/// `ScheduleStore.applyDial`, marked out from the person's own schedules by
/// `Schedule.fromDial`.
///
/// Pure, so every rule is testable without a store, a clock, or a notification
/// centre behind it.
public enum ReminderSeed {
    /// What "now and then" means: three days, spread across the week, with a
    /// gap after each one. Every other day would drift into every day the
    /// moment somebody adds a fourth, and consecutive days would make two
    /// missed mornings look like a broken habit — which is the pressure the
    /// gentle setting exists to avoid.
    public static let gentleDays: Set<Weekday> = [.monday, .wednesday, .friday]

    /// The hour a goal suits, mirroring the bands `HomeSuggestion.goal(forHour:)`
    /// reads the day in — mornings wake up, working hours focus, evenings wind
    /// down, and late is about sleep. Stated rather than derived from those
    /// bands: the useful hour is somewhere inside each stretch, not at the edge
    /// where it starts.
    ///
    /// `reset` has no band of its own, and lands in the afternoon dip that is
    /// the usual reason to want one.
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
    ///
    /// Nil for `never`, and that is the whole of the privacy promise on this
    /// path: no schedule is created, so `ScheduleStore.add` is never called, so
    /// the notification permission prompt — which lives only there — never
    /// appears.
    ///
    /// - Parameter technique: what the reminder opens with, and what decides
    ///   the hour. The person picked its goal a screen ago.
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
