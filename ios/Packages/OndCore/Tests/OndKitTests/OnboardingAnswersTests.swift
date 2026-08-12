import Foundation
@testable import OndKit
import Testing

/// What the flow collects, and — as importantly — what it leaves alone.
///
/// Split from `OnboardingFlowTests`, which is about where the flow goes next.
/// This one is about the value it produces: `UpdateProfile` replaces every
/// column, so the profile onboarding hands over is the thing that can quietly
/// erase answers nobody was asked for, and the fields it does collect have to
/// come out in a shape the server will take.
@MainActor
@Suite("Onboarding answers")
struct OnboardingAnswersTests {
    /// Takes whatever it is given and remembers it, so a test can read what
    /// would have reached the server.
    private struct AcceptingProfiles: ProfileSyncing {
        func fetch() async throws -> Profile {
            .unanswered
        }

        func update(_ profile: Profile) async throws -> Profile {
            profile
        }
    }

    /// A `UserDefaults` nobody else shares, cleared first because suites
    /// persist between runs.
    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "onboarding-answer-tests.\(name)")
        suite?.removePersistentDomain(forName: "onboarding-answer-tests.\(name)")
        return suite ?? .standard
    }

    private func model(_ name: String) -> OnboardingModel {
        OnboardingModel(
            store: ProfileStore(profiles: AcceptingProfiles(), defaults: defaults(name)),
            plus: nil
        )
    }

    /// Goals are sent in the order they were picked, so someone sees their own
    /// ordering back. A `Set` would look identical here and lose it.
    @Test("Toggling goals keeps the order they were picked in")
    func keepsGoalOrder() {
        let model = model("goals")

        model.toggle(.focus)
        model.toggle(.calm)
        model.toggle(.sleep)
        model.toggle(.calm)

        #expect(model.goals == [.focus, .sleep])
        #expect(!model.isSelected(.calm))
    }

    /// The name is a greeting rather than a record: nobody has to give one, a
    /// space is not one, and what reaches the profile is trimmed. The clamp is
    /// the same rule the leaderboard name follows, in the same unit — a name
    /// the server would refuse must be impossible to type.
    @Test("The name is optional, trimmed, and stops at the server's limit")
    func handlesTheGivenName() {
        let model = model("name")

        #expect(model.profile.givenName.isEmpty)
        #expect(!model.hasAnswered, "an untouched flow has nothing to restore over")

        model.givenName = "  Robin  "
        #expect(model.profile.givenName == "Robin")
        #expect(model.hasAnswered)

        model.givenName = "   "
        #expect(model.profile.givenName.isEmpty, "whitespace is not a name")

        model.givenName = String(repeating: "a", count: Profile.maxGivenNameLength + 40)
        #expect(model.givenName.unicodeScalars.count == Profile.maxGivenNameLength)

        // The server refuses a name carrying one of these outright, and a
        // profile it refuses is one whose *every* answer stops syncing — goals,
        // experience and reminders included — silently, for the life of the
        // install. A pasted name arrives cleaned rather than saved and stuck.
        model.givenName = "Robin\tS\u{0}"
        #expect(model.givenName == "RobinS")

        // Not the format characters, which are a wider net: the joiner in a
        // multi-scalar emoji is load-bearing and the server stores it happily.
        model.givenName = "Robin\u{200D}"
        #expect(model.givenName == "Robin\u{200D}")
    }

    /// Never has to be what someone gets by not answering, all the way through
    /// to what is stored. The whole privacy stance rests on the default rather
    /// than on anyone making a choice.
    @Test("An untouched reminder dial stores never")
    func remindersDefaultToNever() {
        let model = model("reminders")

        #expect(model.reminderIntensity == .never)
        #expect(model.profile.reminderIntensity == .never)
    }

    /// The wholesale-replace hazard, from the side onboarding creates it on.
    ///
    /// `UpdateProfile` replaces every column, and this flow asks about four of
    /// the seven. Finishing it therefore has to carry the other three rather
    /// than send blanks — otherwise a reinstall whose restore has already
    /// landed loses the display name, gender and birth band the server was
    /// holding, at the moment the person finishes answering four questions.
    @Test("Finishing never erases the answers this flow does not ask")
    func finishingKeepsTheAnswersItNeverAsks() {
        let store = ProfileStore(profiles: AcceptingProfiles(), defaults: defaults("merge"))
        store.adopt(Profile(
            goals: [.sleep],
            experienceLevel: .occasional,
            reminderIntensity: .gentle,
            intentNote: "I clench my jaw",
            displayName: "puckly-puffin-42",
            birthYearBand: .eighties,
            gender: .nonBinary,
            givenName: "Robin"
        ))

        let model = OnboardingModel(store: store, plus: nil)
        model.toggle(.focus)
        model.givenName = "Sam"

        let answered = model.profile

        #expect(answered.goals == [.focus], "what was asked is the newer answer")
        #expect(answered.givenName == "Sam")
        #expect(answered.experienceLevel == nil, "left unanswered here, so cleared")
        #expect(answered.displayName == "puckly-puffin-42")
        #expect(answered.birthYearBand == .eighties)
        #expect(answered.gender == .nonBinary)
        #expect(answered.intentNote == "I clench my jaw")
    }
}
