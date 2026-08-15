import Foundation
import OndKit
import Testing

/// The Advanced dials write these, the catalogue can change underneath them, and
/// nothing between the two revalidates. Applying them is therefore the one place
/// a stale preference could put a duration on the wrong phase or a hold outside
/// its safe range.
@Suite("Applying a person's dialled-in overrides")
struct TechniqueOverridesTests {
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

    @Test("No overrides is the curated technique, unchanged")
    func fallsBackToTheCatalogue() {
        let dialled = Self.technique.dialled(with: nil)

        #expect(dialled.stages == Self.technique.stages)
        #expect(dialled.recommendedRounds == 1)
        #expect(dialled.slug == Self.technique.slug, "a dialled technique is the same technique")
    }

    @Test("A dialled technique plays what the person chose")
    func appliesTheDial() throws {
        let overrides = TechniqueOverrides(
            stages: [StageDialling(phaseDurationsMs: [5000, 8000], cycles: 20)],
            rounds: 1
        )

        let stage = try #require(Self.technique.dialled(with: overrides).stages.first)

        #expect(stage.phases.map(\.duration) == [.milliseconds(5000), .milliseconds(8000)])
        #expect(stage.cycles == 20)
        #expect(
            stage.phases[0].range == Self.technique.stages[0].phases[0].range,
            "a dial moves the duration, never the range it moves within"
        )
    }

    /// The evidence-based range is the product's safety story. A stored value
    /// from before it was tightened must land inside the new one, not outside.
    @Test("A dial is clamped into the range the catalogue seeded")
    func clampsIntoTheSeededRange() throws {
        let overrides = TechniqueOverrides(
            stages: [StageDialling(phaseDurationsMs: [99999, 1], cycles: 9999)],
            rounds: 99
        )

        let dialled = Self.technique.dialled(with: overrides)
        let stage = try #require(dialled.stages.first)

        #expect(stage.phases.map(\.duration) == [.milliseconds(5000), .milliseconds(6000)])
        #expect(stage.cycles == TechniqueOverrides.cycleRange.upperBound)
        #expect(dialled.recommendedRounds == TechniqueOverrides.roundRange.upperBound)
    }

    /// The one case parallel arrays exist to make detectable: a technique that
    /// gained a phase since the preference was written. There is no way to know
    /// which stored duration belonged to which new phase, so the whole
    /// preference goes rather than half of it landing on the wrong beat — and
    /// the rounds go with the stages, or a session plays curated stages for a
    /// count nobody chose.
    @Test("Overrides that no longer fit the technique are dropped whole")
    func dropsOverridesThatNoLongerFit() {
        let stale = TechniqueOverrides(
            stages: [StageDialling(phaseDurationsMs: [5000], cycles: 20)],
            rounds: 7
        )

        let dialled = Self.technique.dialled(with: stale)

        #expect(dialled.stages == Self.technique.stages)
        #expect(dialled.recommendedRounds == 1)
        #expect(Self.technique.resolving(stale) == Self.technique.curatedOverrides)
    }

    /// Every Begin in the app dials before it gates, so a dialled copy that let
    /// `requires` fall back to its `.free` default opened the whole catalogue to
    /// anybody who reached a locked technique from home or from Advanced — with
    /// the list still drawing the lock beside it.
    @Test("Dialling a locked technique leaves it locked")
    func keepsTheTierItRequires() {
        let locked = Technique(
            id: Self.technique.id,
            slug: Self.technique.slug,
            name: Self.technique.name,
            summary: "",
            goal: .sleep,
            stages: Self.technique.stages,
            recommendedRounds: 1,
            requires: .plus
        )

        #expect(locked.dialled(with: nil).isUnlocked(for: .free) == false)
        #expect(locked.dialled(with: locked.curatedOverrides).requires == .plus)
    }

    @Test("The curated overrides describe the technique as seeded")
    func curatedOverridesRoundTrip() {
        let curated = Self.technique.curatedOverrides

        #expect(curated.stages == [StageDialling(phaseDurationsMs: [4000, 6000], cycles: 12)])
        #expect(curated.rounds == 1)
        #expect(Self.technique.dialled(with: curated).stages == Self.technique.stages)
    }

    /// Releases before `StageDialling` stored two arrays whose matching indices
    /// described one stage. A valid old payload must retain every number.
    @Test("Legacy parallel arrays migrate without losing a dial")
    func legacyArraysDecodeIntoStages() throws {
        let legacy = Data(
            #"{"phaseDurationsMs":[[5000,8000],[1200]],"stageCycles":[20,3],"rounds":2}"#
                .utf8
        )

        let decoded = try JSONDecoder().decode(TechniqueOverrides.self, from: legacy)

        #expect(decoded == TechniqueOverrides(
            stages: [
                StageDialling(phaseDurationsMs: [5000, 8000], cycles: 20),
                StageDialling(phaseDurationsMs: [1200], cycles: 3),
            ],
            rounds: 2
        ))
    }

    /// A successfully migrated value writes only the representation current
    /// releases understand, so the parallel arrays disappear on the next save.
    @Test("Encoding writes only stage-shaped dialling")
    func encodingUsesOnlyStages() throws {
        let encoded = try JSONEncoder().encode(TechniqueOverrides(
            stages: [StageDialling(phaseDurationsMs: [5000, 8000], cycles: 20)],
            rounds: 2
        ))
        let json = try #require(String(bytes: encoded, encoding: .utf8))

        #expect(json.contains(#""stages""#))
        #expect(!json.contains(#""phaseDurationsMs":[["#))
        #expect(!json.contains(#""stageCycles""#))
    }

    /// Unequal old arrays never described a complete set of stages. Refusing
    /// them keeps an orphan duration or cycle from silently moving stages.
    @Test("Misaligned legacy arrays are unreadable")
    func misalignedLegacyArraysFail() {
        let legacy = Data(
            #"{"phaseDurationsMs":[[5000],[6000]],"stageCycles":[20],"rounds":2}"#.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TechniqueOverrides.self, from: legacy)
        }
    }
}
