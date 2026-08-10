import Foundation

/// The reminder dial: where it stands, and what moving it does.
///
/// Its own type rather than a field on `ProfileEditModel`, because the two
/// screens want opposite things of the same value. The profile form edits a
/// draft and sends the whole of it on one Save, since the server may hand back
/// something other than what it was given. The dial answers a question asked of
/// Settings — how often should this app speak to me — and its answer is never
/// one the server polices, so making somebody press Save to be reminded less
/// often would be ceremony over nothing.
///
/// Storage is still the profile, which is where the answer has always lived and
/// where a reinstall reads it back from. Nothing is snapshotted: the position is
/// read through `ProfileStore` on every access, so the dial and a profile form
/// open over it cannot disagree about where it stands.
///
/// A struct with no state of its own, so the view that draws the dial can build
/// one in place. Observation still works, because reading `intensity` reads
/// `ProfileStore.profile` and it is that access SwiftUI records.
@MainActor
public struct ReminderDial {
    private let profiles: ProfileStore
    private let schedules: ScheduleStore
    private let catalogue: TechniqueListModel

    /// - Parameters:
    ///   - profiles: where the position is stored, and what carries it to the
    ///     server on the profile.
    ///   - schedules: where a move lands (`ScheduleStore.applyDial`).
    ///   - catalogue: what a newly created reminder opens with, on
    ///     `OnboardingModel`'s terms. Only read when the dial moves off `never`
    ///     with no dial-owned schedule left to reshape.
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

    /// Stores the new position and reshapes the one schedule the dial owns.
    ///
    /// The schedule follows the save rather than racing it, and follows it
    /// whatever the server said: reminders are local through and through, and
    /// the refusals a profile can draw are about a display name this control
    /// does not offer.
    ///
    /// The catalogue is only awaited when a reminder may need creating —
    /// `never` is the delete path, and blocking on a fetch whose answer is about
    /// to be discarded would hold the screen for nothing.
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
