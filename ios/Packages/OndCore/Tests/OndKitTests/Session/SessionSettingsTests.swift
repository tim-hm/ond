import Foundation
@testable import OndKit
import Testing

/// What a deletion has to reach in the preferences, and what survives a relaunch
/// on the way there. Worth pinning because the failure is silent in both
/// directions: a preference that does not survive a relaunch is a switch that will
/// not stay where it was put, and one that survives a deletion is a fresh install
/// that still knows how the last person practised.
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
            stages: [StageDialling(phaseDurationsMs: [3000, 7000], cycles: 8)],
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

    /// The legacy payload is the exact dictionary stored by released builds.
    /// Loading keeps its dials, and the next write removes both parallel keys.
    @Test("Stored legacy overrides migrate on their next save")
    func storedLegacyOverridesMigrate() throws {
        let defaults = try defaults()
        defaults.set(
            Data(
                #"{"extended-exhale":{"phaseDurationsMs":[[3000,7000]],"stageCycles":[8],"rounds":1}}"#
                    .utf8
            ),
            forKey: "session.techniqueOverrides"
        )

        let settings = SessionSettings(defaults: defaults)
        let restored = try #require(settings.overrides(for: Self.technique))
        #expect(restored.stages == [
            StageDialling(phaseDurationsMs: [3000, 7000], cycles: 8),
        ])

        settings.setOverrides(restored, for: Self.technique)
        let saved = try #require(defaults.data(forKey: "session.techniqueOverrides"))
        let json = try #require(String(bytes: saved, encoding: .utf8))
        #expect(json.contains(#""stages""#))
        #expect(!json.contains(#""stageCycles""#))
        #expect(!json.contains(#""phaseDurationsMs":[["#))
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

    /// `UserDefaults.bool(forKey:)` answers false for an absent key, which is
    /// indistinguishable from a stored false — so a preference that ships *on*
    /// would be silenced for every install until somebody found the switch and
    /// flipped it twice. Both directions, because `flag(forKey:default:)` is
    /// what makes either one work and one assertion cannot show it.
    @Test("A switch stays where it was put, whichever way it ships")
    func aChoiceSurvivesARelaunch() throws {
        let defaults = try defaults()

        #expect(SessionSettings(defaults: defaults).asksHowYouFeel, "on by default")
        #expect(!SessionSettings(defaults: defaults).showsWristPulse, "off by default")

        SessionSettings(defaults: defaults).asksHowYouFeel = false
        SessionSettings(defaults: defaults).showsWristPulse = true

        #expect(!SessionSettings(defaults: defaults).asksHowYouFeel)
        #expect(SessionSettings(defaults: defaults).showsWristPulse)
    }

    @Test("Moved preference vocabularies keep their stored keys and values")
    func movedVocabulariesKeepTheirPersistenceContract() throws {
        let defaults = try defaults()
        let settings = SessionSettings(defaults: defaults)

        settings.appearance = .dark
        settings.breathVisual = .sweeping
        settings.cueMode = .visualOnly
        settings.guidance = .essentials

        #expect(defaults.string(forKey: "app.appearance") == "dark")
        #expect(defaults.string(forKey: "session.breathVisual") == "ring")
        #expect(defaults.string(forKey: "session.cueMode") == "visualOnly")
        #expect(defaults.string(forKey: "session.guidance") == "essentials")

        let relaunched = SessionSettings(defaults: defaults)
        #expect(relaunched.appearance == .dark)
        #expect(relaunched.breathVisual == .sweeping)
        #expect(relaunched.cueMode == .visualOnly)
        #expect(relaunched.guidance == .essentials)

        settings.breathVisual = .scaling
        #expect(defaults.string(forKey: "session.breathVisual") == "sphere")
    }

    /// The list a deletion walks is `Key.allCases`, so this walks it too: a
    /// preference added to the class arrives here on its own rather than
    /// waiting for somebody to remember to assert it. What it cannot catch is
    /// a key nobody added to the enum — which is why the enum is the only way
    /// to name one.
    @Test("A deletion leaves no key of this store on disk")
    func erasingLeavesNoKeyBehind() async throws {
        let defaults = try defaults()
        let settings = SessionSettings(defaults: defaults)
        for key in SessionSettings.Key.allCases {
            defaults.set("touched", forKey: key.rawValue)
        }

        await settings.erase()

        for key in SessionSettings.Key.allCases {
            #expect(defaults.object(forKey: key.rawValue) == nil, "\(key.rawValue) survived")
        }
    }
}
