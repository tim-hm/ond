@testable import OndKit
import Testing

@Suite("Subscription tiers")
struct SubscriptionTierTests {
    /// Every gate in the app is a comparison rather than an equality, so the
    /// ordering is load-bearing. A Coach subscriber must satisfy a Plus gate —
    /// getting this backwards would lock the catalogue for the people paying
    /// most for it.
    @Test("A higher tier satisfies a lower gate")
    func orderingIsALadder() {
        #expect(SubscriptionTier.coach > .plus)
        #expect(SubscriptionTier.plus > .free)
        #expect(SubscriptionTier.purchasable == [.plus, .coach])
    }

    /// The assistant is free while the featureset settles, and this says so out
    /// loud. The ladder above stays intact and tested precisely so that closing
    /// the gate again is this one line — which is the point of asserting it: a
    /// tier that drifted back up without anybody deciding would shut the coach
    /// off for everybody, and it should have to fail a test on the way.
    @Test("Nothing gates the assistant")
    func theAssistantIsFree() {
        #expect(SubscriptionTier.assistant == .free)
    }
}

@Suite("What a tier unlocks")
struct TechniqueGatingTests {
    /// `requires` is defaulted here exactly as it is on `Technique`, so the
    /// no-argument call pins the proto zero value's direction: a technique that
    /// arrives saying nothing is free.
    private func technique(requires: SubscriptionTier = .free) -> Technique {
        Technique(
            id: "t",
            slug: "t",
            name: "T",
            summary: "",
            goal: .calm,
            stages: [Stage(phases: [Phase(kind: .inhale, duration: .seconds(4))], cycles: 1)],
            recommendedRounds: 1,
            requires: requires
        )
    }

    /// The gate is a comparison, so paying more never opens less.
    @Test("A locked technique opens at its tier and above")
    func lockedOpensAtItsTierAndAbove() {
        let locked = technique(requires: .plus)

        #expect(!locked.isUnlocked(for: .free))
        #expect(locked.isUnlocked(for: .plus))
        #expect(locked.isUnlocked(for: .coach))
    }

    /// The default is unlocked, matching the proto's zero value: a technique
    /// that arrives without the field — from an older server, or a truncated
    /// message — must not be one somebody is asked to pay for.
    @Test("A technique with nothing said about it is free")
    func theDefaultIsUnlocked() {
        #expect(technique(requires: .free).isUnlocked(for: .free))

        #expect(technique().isUnlocked(for: .free))
    }
}
