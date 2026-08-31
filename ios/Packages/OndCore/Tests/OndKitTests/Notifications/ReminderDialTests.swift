import Foundation
@testable import OndKit
import Testing

/// The reminder dial after onboarding: moving it reshapes the one schedule it owns,
/// and nothing else. The boundary under test is ownership. The dial's reminder is
/// an ordinary schedule the person may edit or delete, and the person's own
/// schedules are ones the dial must never touch — a dial that reached into a
/// hand-made arrangement would be worse than the inert one it replaced.
@MainActor
@Suite("Moving the reminder dial")
struct ReminderDialTests {
    private final class NotifierSpy: ScheduleNotifying, @unchecked Sendable {
        private(set) var synced: [[Schedule]] = []
        private(set) var authorizationRequests = 0

        func requestAuthorization() async -> Bool {
            authorizationRequests += 1
            return true
        }

        func sync(_ schedules: [Schedule]) async {
            synced.append(schedules)
        }
    }

    private struct StubReader: TechniqueReading {
        let techniques: [Technique]

        func localTechniques() async -> [Technique]? {
            techniques
        }

        func refreshTechniques() async throws -> [Technique] {
            techniques
        }
    }

    private struct AcceptingProfiles: ProfileSyncing {
        func fetch() async throws -> Profile {
            .unanswered
        }

        func update(_ profile: Profile) async throws -> Profile {
            profile
        }
    }

    private func technique(slug: TechniqueSlug, goal: TechniqueGoal) -> Technique {
        Technique(
            id: TechniqueId(rawValue: slug.rawValue),
            slug: slug,
            name: slug.rawValue.capitalized,
            summary: "",
            goal: goal,
            stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
            recommendedRounds: 1
        )
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "reminder-dial-tests.\(name)")
        suite?.removePersistentDomain(forName: "reminder-dial-tests.\(name)")
        return suite ?? .standard
    }

    private func dialSchedule(hour: Int = 18, enabled: Bool = true) -> Schedule {
        Schedule(
            techniqueSlug: "box-breathing",
            techniqueName: "Box breathing",
            hour: hour,
            minute: 0,
            weekdays: ReminderSeed.gentleDays,
            isEnabled: enabled,
            fromDial: true
        )
    }

    private func ownSchedule() -> Schedule {
        Schedule(
            techniqueSlug: "four-seven-eight",
            techniqueName: "4-7-8",
            hour: 22,
            minute: 30,
            weekdays: [.sunday]
        )
    }

    @Test("Never removes the dial's reminder and only it")
    func neverRemovesOnlyTheDialsOwn() {
        let store = ScheduleStore(notifier: NotifierSpy(), defaults: defaults("never"))
        store.add(dialSchedule())
        store.add(ownSchedule())

        store.applyDial(.never, technique: nil)

        #expect(store.schedules.count == 1)
        #expect(store.schedules.first?.fromDial == false, "the hand-made schedule survives")
    }

    /// The dial governs frequency and nothing else: a time or technique the
    /// person put on its reminder is theirs, and a pause is undone because
    /// moving the dial is an explicit ask to be reminded at that cadence.
    @Test("Moving the dial reshapes days only, and wakes a paused reminder")
    func reshapesDaysKeepingThePersonsEdits() {
        let spy = NotifierSpy()
        let store = ScheduleStore(notifier: spy, defaults: defaults("reshape"))
        store.add(dialSchedule(hour: 6, enabled: false))
        let asksBefore = spy.authorizationRequests

        store.applyDial(.daily, technique: nil)

        let owned = store.schedules.first { $0.fromDial }
        #expect(owned?.weekdays == Set(Weekday.allCases))
        #expect(owned?.hour == 6, "the person's edited time survives the frequency change")
        #expect(owned?.isEnabled == true)
        #expect(
            spy.authorizationRequests == asksBefore,
            "reshaping an existing reminder is not the moment to ask for permission again"
        )
    }

    /// The deleted-then-redialled case: the dial recreates its reminder, and
    /// because a schedule is being created, the permission promise comes due
    /// exactly as it does at onboarding.
    @Test("Moving off never with nothing to reshape creates the reminder")
    func createsWhenNothingSurvives() async throws {
        let spy = NotifierSpy()
        let store = ScheduleStore(notifier: spy, defaults: defaults("create"))

        store.applyDial(.gentle, technique: technique(slug: "box-breathing", goal: .calm))

        let owned = try #require(store.schedules.first { $0.fromDial })
        #expect(owned.weekdays == ReminderSeed.gentleDays)
        #expect(owned.hour == ReminderSeed.hour(for: .calm))

        // `add`'s authorization ask is fire-and-forget; give it a beat.
        try await settle { spy.authorizationRequests == 1 }
        #expect(spy.authorizationRequests == 1)
    }

    /// The mark must survive the store's own persistence: an ownership that
    /// evaporated on relaunch would recreate the orphan the editor fix
    /// (`ScheduleEditorView.built`) exists to prevent.
    @Test("The dial's ownership survives a relaunch")
    func ownershipPersists() {
        let suite = defaults("roundtrip")
        ScheduleStore(notifier: NotifierSpy(), defaults: suite).add(dialSchedule())

        let reopened = ScheduleStore(notifier: NotifierSpy(), defaults: suite)
        #expect(reopened.schedules.first?.fromDial == true)
    }

    /// A list persisted before the mark existed must keep decoding — under
    /// `DefaultsJSONStore` a decode failure would read as no schedules at all,
    /// which for a routine somebody keeps is the worst available answer.
    @Test("A list stored before the dial mark still decodes, unowned")
    func legacyListsDecode() {
        let suite = defaults("legacy")
        let legacy = """
        [{"id":"7d100000-0000-4000-8000-000000000001","techniqueSlug":"box-breathing",\
        "techniqueName":"Box breathing","hour":7,"minute":0,"weekdays":[2,4,6],"isEnabled":true}]
        """
        suite.set(Data(legacy.utf8), forKey: "schedules.list")

        let store = ScheduleStore(notifier: NotifierSpy(), defaults: suite)

        #expect(store.schedules.count == 1)
        #expect(store.schedules.first?.fromDial == false)
    }

    /// The whole path a turn of the dial in Settings takes: the position is
    /// stored on the profile, and the reminder is reshaped to match — waiting on
    /// the catalogue the way the onboarding seed does, because a created
    /// reminder has to open something.
    @Test("Moving the dial stores the position and lands it on the schedule list")
    func movingTheDialStoresAndReshapes() async {
        let schedules = ScheduleStore(notifier: NotifierSpy(), defaults: defaults("move"))
        let profiles = ProfileStore(
            profiles: AcceptingProfiles(),
            defaults: defaults("move-profile")
        )
        let dial = ReminderDial(
            profiles: profiles,
            schedules: schedules,
            catalogue: TechniqueListModel(
                techniques: StubReader(techniques: [technique(slug: "box-breathing", goal: .calm)])
            )
        )

        await dial.move(to: .daily)

        #expect(dial.intensity == .daily, "the dial reads back where it was left")
        #expect(profiles.profile.reminderIntensity == .daily)
        #expect(schedules.schedules.first { $0.fromDial }?.weekdays == Set(Weekday.allCases))
    }

    /// The dial writes through on the turn, so the position it is set to has to
    /// be the position it reports — anything else and a person who moves it,
    /// leaves Settings and comes back finds it somewhere they did not put it.
    @Test("Moving the dial to where it already stands touches nothing")
    func unmovedDialTouchesNothing() async {
        let schedules = ScheduleStore(notifier: NotifierSpy(), defaults: defaults("unmoved"))
        let profiles = ProfileStore(
            profiles: AcceptingProfiles(),
            defaults: defaults("unmoved-profile")
        )
        let dial = ReminderDial(
            profiles: profiles,
            schedules: schedules,
            catalogue: TechniqueListModel(techniques: StubReader(techniques: []))
        )

        await dial.move(to: dial.intensity)

        #expect(schedules.schedules.isEmpty)
    }

    /// Saving the profile from the form no longer reaches the schedules at all:
    /// the dial is not on that screen, and a Save that reshaped a reminder as a
    /// side effect of a display-name change would be the split the move undid.
    @Test("Saving the profile form leaves the schedule list alone")
    func profileSaveTouchesNoSchedules() async {
        let schedules = ScheduleStore(notifier: NotifierSpy(), defaults: defaults("form"))
        let profiles = ProfileStore(
            profiles: AcceptingProfiles(),
            defaults: defaults("form-profile")
        )
        let model = ProfileEditModel(store: profiles)

        model.draft.displayName = "Åsa"
        await model.save()

        #expect(schedules.schedules.isEmpty)
    }
}
