import Foundation
@testable import OndKit
import Testing

/// What a deletion has to reach in the preferences, and what survives a
/// relaunch on the way there.
///
/// Worth pinning because the failure is silent in both directions: a
/// preference that does not survive a relaunch is a switch that will not stay
/// where it was put, and one that survives a deletion is a fresh install that
/// still knows how the last person practised.
@Suite("Session settings")
@MainActor
struct SessionSettingsTests {
    /// One technique to dial, with a range each phase can actually move
    /// within — `setOverrides` drops anything matching the curated defaults,
    /// so the values below have to differ from these.
    private static let technique = Technique(
        id: "id",
        slug: "extended-exhale",
        name: "Extended Exhale",
        summary: "",
        goal: .sleep,
        stages: [
            Stage(
                phases: [
                    Phase(
                        kind: .inhale,
                        duration: .milliseconds(4000),
                        range: .milliseconds(3000) ... .milliseconds(5000)
                    ),
                    Phase(
                        kind: .exhale,
                        duration: .milliseconds(6000),
                        range: .milliseconds(6000) ... .milliseconds(8000)
                    ),
                ],
                cycles: 12
            ),
        ],
        recommendedRounds: 1
    )

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "session-settings-tests.\(UUID().uuidString)"))
    }

    /// The dialled techniques are the part of this that is somebody's practice
    /// rather than their taste, and the part that was left behind before this
    /// store joined the deletion list.
    @Test("Deleting the account forgets every technique the person dialled")
    func erasingForgetsTheDials() async throws {
        let defaults = try defaults()
        let settings = SessionSettings(defaults: defaults)
        let dialled = TechniqueOverrides(
            phaseDurationsMs: [[3000, 7000]],
            stageCycles: [8],
            rounds: 1
        )
        settings.setOverrides(dialled, for: Self.technique)

        await settings.erase()

        #expect(settings.overrides(for: Self.technique) == nil, "in this process")
        #expect(
            SessionSettings(defaults: defaults).overrides(for: Self.technique) == nil,
            "and on the next launch"
        )
    }

    /// Both halves of `PersonalStore`, over the preference that ships on: the
    /// in-memory copy and the stored one. Off is the interesting direction —
    /// a defaulted-on switch reads as on again whether or not the key went, so
    /// only the choice to be left alone can show that the key really did.
    @Test("Deleting the account puts every switch back to its default")
    func erasingRestoresTheDefaults() async throws {
        let defaults = try defaults()
        let settings = SessionSettings(defaults: defaults)
        settings.asksHowYouFeel = false
        settings.showsWristPulse = true
        settings.appearance = .dark
        settings.cueMode = .visualOnly

        await settings.erase()

        #expect(settings.asksHowYouFeel)
        #expect(!settings.showsWristPulse)
        #expect(settings.appearance == .system)
        #expect(settings.cueMode == .hapticsAndAudio)

        let relaunched = SessionSettings(defaults: defaults)
        #expect(relaunched.asksHowYouFeel)
        #expect(!relaunched.showsWristPulse)
        #expect(relaunched.appearance == .system)
        #expect(relaunched.cueMode == .hapticsAndAudio)
    }

    /// The trap on the other side of the same key: a preference that ships
    /// *off* must still remember being turned on, which `flag(forKey:default:)`
    /// answers and a bare `bool(forKey:)` cannot distinguish from an absent
    /// key it has just erased.
    @Test("A switch stays where it was put across a relaunch")
    func aChoiceSurvivesARelaunch() throws {
        let defaults = try defaults()
        SessionSettings(defaults: defaults).showsWristPulse = true

        #expect(SessionSettings(defaults: defaults).showsWristPulse)
    }
}
