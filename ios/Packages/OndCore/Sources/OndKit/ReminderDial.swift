import Foundation

/// The reminder dial: where it stands, and what moving it does. Its own type
/// because the profile form edits a draft behind one Save while the dial
/// applies at once — the server never polices this answer. Storage is still the
/// profile, read through `ProfileStore` on every access, so the dial and an
/// open profile form cannot disagree; that access is what SwiftUI records.
@MainActor
public struct ReminderDial {
    private let profiles: ProfileStore
    private let schedules: ScheduleStore
    private let catalogue: TechniqueListModel

    /// - Parameter catalogue: what a newly created reminder opens with, on
    ///   `OnboardingModel`'s terms. Only read when the dial moves off `never`
    ///   with no dial-owned schedule left to reshape.
    public init(profiles: ProfileStore, schedules: ScheduleStore, catalogue: TechniqueListModel) {
        self.profiles = profiles
        self.schedules = schedules
        self.catalogue = catalogue
    }

    /// Where the dial stands, read from the stored profile rather than mirrored
    /// beside it.
    public var intensity: ReminderIntensity {
        profiles.profile.reminderIntensity
    }

    /// Makes the schedule the stored position implies, holding the invariant
    /// that a profile off `never` has one: the standalone safety-terms first run
    /// used to leave "once a day" with no appointment. Awaits the catalogue —
    /// the first launch's fetch may be in the air — and re-checks emptiness after:
    /// a dial moved mid-fetch lands its own schedule. `never` never reaches `add`.
    public func seedIfNeeded() async {
        guard schedules.schedules.isEmpty else { return }

        let profile = profiles.profile
        guard ReminderSeed.days(for: profile.reminderIntensity) != nil,
              let technique = await catalogue.reminderTechnique(forFirstOf: profile.goals),
              let seeded = ReminderSeed.schedule(
                  for: profile.reminderIntensity,
                  technique: technique
              ),
              schedules.schedules.isEmpty
        else {
            return
        }

        schedules.add(seeded)
    }

    /// Stores the new position and reshapes the one schedule the dial owns. The
    /// schedule follows the save whatever the server said: reminders are local,
    /// and the refusals a profile can draw are about a display name this control
    /// does not offer. The catalogue is awaited only when a reminder may need
    /// creating — `never` is the delete path, and would block on a discarded fetch.
    public func move(to intensity: ReminderIntensity) async {
        guard intensity != self.intensity else { return }

        var profile = profiles.profile
        profile.reminderIntensity = intensity
        await profiles.save(profile)

        guard ReminderSeed.days(for: intensity) != nil else {
            schedules.applyDial(intensity, technique: nil)
            return
        }

        let technique = await catalogue.reminderTechnique(forFirstOf: profile.goals)
        schedules.applyDial(intensity, technique: technique)
    }
}
