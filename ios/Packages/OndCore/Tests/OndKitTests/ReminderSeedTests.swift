import Foundation
@testable import OndKit
import Testing

/// The reminder dial, from the answer to the appointment it makes.
///
/// The `never` case is the one that must never break: it is the app's whole
/// privacy stance on notifications, and the way it fails is silent — a schedule
/// nobody asked for, or worse, a system permission prompt in front of somebody
/// who said no.
@MainActor
@Suite("Seeding a reminder from the onboarding dial")
struct ReminderSeedTests {
    /// Counts the asks as well as the syncs: permission belongs to the moment a
    /// schedule is created, and a seed that created none must not have asked.
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

        func listTechniques() async throws -> [Technique] {
            techniques
        }

        func listFoundations() async throws -> [FoundationTopic] {
            []
        }

        func listRoutes() async throws -> Routes {
            .none
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

    private func technique(slug: String, goal: TechniqueGoal) -> Technique {
        Technique(
            id: slug,
            slug: slug,
            name: slug.capitalized,
            summary: "",
            goal: goal,
            stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
            recommendedRounds: 1
        )
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "reminder-seed-tests.\(name)")
        suite?.removePersistentDomain(forName: "reminder-seed-tests.\(name)")
        return suite ?? .standard
    }

    /// An unloaded catalogue, deliberately: a first launch answers the last
    /// question while the fetch may still be in the air, so the seed has to
    /// wait for it rather than read whatever is there at that instant.
    private func catalogue() -> TechniqueListModel {
        TechniqueListModel(
            techniques: StubReader(techniques: [
                technique(slug: "box-breathing", goal: .calm),
                technique(slug: "four-seven-eight", goal: .sleep),
                technique(slug: "bellows-breath", goal: .energy),
            ])
        )
    }

    /// Polls until the seed's fire-and-forget task has run, the same way the
    /// schedule tests wait on the store's notifier.
    private func waitForSchedule(in store: ScheduleStore) async throws {
        for _ in 0 ..< 200 {
            if !store.schedules.isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for the seeded schedule")
    }

    /// Walks the real flow to the end with the answers given.
    private func complete(
        goals: [TechniqueGoal],
        reminders: ReminderIntensity,
        into schedules: ScheduleStore,
        defaults suite: UserDefaults
    ) {
        let model = OnboardingModel(
            store: ProfileStore(profiles: AcceptingProfiles(), defaults: suite),
            schedules: schedules,
            catalogue: catalogue()
        )

        // The welcome asks nothing — walk through to the first question rather
        // than counting the screens in front of it.
        while model.step != .you {
            model.advance()
        }
        for goal in goals {
            model.toggle(goal)
        }
        model.experienceLevel = .new
        model.advance()

        #expect(model.step == .optIns, "the dial lives with the opt-ins")
        model.reminderIntensity = reminders
        // To the very end, because that is where the seeding happens now — see
        // `theSeedWaitsForTheEnd` below for why it moved.
        while !model.isFinished {
            model.advance()
        }
    }

    /// The seed is the one thing in this flow that raises a system prompt, and
    /// it is deliberately the last thing that happens: `ScheduleStore.add` asks
    /// for notification permission, and at finish that sheet lands over Home
    /// rather than over the screen selling a subscription.
    @Test("Nothing is seeded until the flow is finished")
    func theSeedWaitsForTheEnd() async throws {
        let spy = NotifierSpy()
        let schedules = ScheduleStore(notifier: spy, defaults: defaults("timing"))
        let model = OnboardingModel(
            store: ProfileStore(
                profiles: AcceptingProfiles(),
                defaults: defaults("timing-profile")
            ),
            schedules: schedules,
            catalogue: catalogue()
        )

        while model.step != .optIns {
            model.advance()
        }
        model.reminderIntensity = .daily
        model.advance()
        model.advance()

        #expect(model.step == .safety)
        // Long enough for the fire-and-forget task an early seed would have
        // started.
        try await Task.sleep(for: .milliseconds(50))
        #expect(schedules.schedules.isEmpty)
        #expect(spy.authorizationRequests == 0, "no prompt over the offer")

        model.advance()
        try await waitForSchedule(in: schedules)

        #expect(schedules.schedules.count == 1)
    }

    /// The promise the onboarding copy makes in as many words: leave the dial
    /// where it is and nothing happens, the permission prompt included.
    @Test("Never creates no schedule and asks for nothing")
    func neverIsSilent() async throws {
        let spy = NotifierSpy()
        let schedules = ScheduleStore(notifier: spy, defaults: defaults("never"))

        complete(
            goals: [.sleep],
            reminders: .never,
            into: schedules,
            defaults: defaults("never-profile")
        )
        // Long enough for the fire-and-forget task an `add` would have started.
        try await Task.sleep(for: .milliseconds(50))

        #expect(schedules.schedules.isEmpty)
        #expect(spy.authorizationRequests == 0, "nobody asked for a nudge")
        #expect(spy.synced.isEmpty)
    }

    /// The other two settings, at the seam where they differ: what they ask for
    /// is a number of days, and the copy promises "an occasional nudge" and
    /// "one reminder a day" respectively.
    @Test("The dial decides how often, and only that")
    func intensityDecidesTheDays() {
        let calm = technique(slug: "box-breathing", goal: .calm)

        #expect(ReminderSeed.schedule(for: .never, technique: calm) == nil)
        #expect(ReminderSeed.schedule(for: .gentle, technique: calm)?.weekdays == [
            .monday,
            .wednesday,
            .friday,
        ])
        #expect(
            ReminderSeed.schedule(for: .daily, technique: calm)?.weekdays
                == Set(Weekday.allCases)
        )
    }

    /// A reminder to sleep at seven in the morning would be worse than none.
    @Test(
        "The hour follows the technique's goal",
        arguments: [
            (goal: TechniqueGoal.energy, hour: 7),
            (goal: .focus, hour: 12),
            (goal: .reset, hour: 15),
            (goal: .calm, hour: 18),
            (goal: .sleep, hour: 21),
        ]
    )
    func hourFollowsTheGoal(goal: TechniqueGoal, hour: Int) {
        let seeded = ReminderSeed.schedule(
            for: .daily,
            technique: technique(slug: "any", goal: goal)
        )

        #expect(seeded?.hour == hour)
        #expect(seeded?.minute == 0)
    }

    /// The whole point of the item: an answer on the dial becomes something a
    /// person can find, edit, and delete in Settings — named after the goal they
    /// picked one screen earlier.
    @Test("Finishing with a nudge leaves exactly one editable schedule")
    func finishingSeedsTheSchedule() async throws {
        let spy = NotifierSpy()
        let schedules = ScheduleStore(notifier: spy, defaults: defaults("seed"))

        complete(
            goals: [.sleep],
            reminders: .daily,
            into: schedules,
            defaults: defaults("seed-profile")
        )
        try await waitForSchedule(in: schedules)

        #expect(schedules.schedules.count == 1)
        let seeded = try #require(schedules.schedules.first)
        #expect(seeded.techniqueSlug == "four-seven-eight")
        #expect(seeded.hour == 21)
        #expect(seeded.isEnabled)

        // The permission promise comes due at the store's `add`, which is where
        // every other schedule asks — onboarding adds no prompt site of its own.
        for _ in 0 ..< 200 {
            if spy.authorizationRequests > 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(spy.authorizationRequests == 1)

        // A person who already keeps schedules has an arrangement of their own,
        // and the flow does not add to it.
        complete(
            goals: [.calm],
            reminders: .daily,
            into: schedules,
            defaults: defaults("seed-profile-again")
        )
        try await Task.sleep(for: .milliseconds(50))
        #expect(schedules.schedules == [seeded])
    }

    /// Naming no goal is an answer the flow takes, and somebody who gave it can
    /// still want a nudge. The seed has to name a technique anyway, so it falls
    /// back to calm — the one aim that suits an unknown reason for being here —
    /// and lands on calm's hour rather than on nothing.
    @Test("With no goal named, the nudge is still seeded")
    func noGoalStillSeedsANudge() async throws {
        let spy = NotifierSpy()
        let schedules = ScheduleStore(notifier: spy, defaults: defaults("no-goal"))

        complete(
            goals: [],
            reminders: .daily,
            into: schedules,
            defaults: defaults("no-goal-profile")
        )
        try await waitForSchedule(in: schedules)

        let seeded = try #require(schedules.schedules.first)
        #expect(seeded.techniqueSlug == "box-breathing")
        #expect(seeded.hour == 18)
    }
}
