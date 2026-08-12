@testable import OndKit
import Testing

@Suite("Subscription tiers")
struct SubscriptionTierTests {
    /// Every gate in the app is a comparison rather than an equality, so the
    /// ordering is load-bearing. Getting it backwards would give away every paid
    /// feature to everybody, and nothing else would notice.
    @Test("A subscriber satisfies a gate the free tier does not")
    func orderingIsALadder() {
        #expect(SubscriptionTier.plus > .free)
        #expect(SubscriptionTier.allCases == [.free, .plus])
    }

    /// The four levers, pinned individually.
    ///
    /// Not one assertion over a list: each is a product decision about a
    /// distinct feature, and a test that read them as a set would pass just as
    /// happily with two of them swapped. Together they say what önd+ is — what
    /// costs the server per use — and any of them drifting back to `.free`
    /// gives that feature away silently.
    @Test("The four levers are what önd+ sells")
    func theLeversPriceWhatCostsUsMoney() {
        #expect(SubscriptionTier.assistant == .plus, "the coach spends on a language model")
        #expect(SubscriptionTier.leaderboards == .plus, "a board is a fold across everybody")
        #expect(SubscriptionTier.healthTrends == .plus, "trends ride into the coach's briefing")
        #expect(SubscriptionTier.watchConnected == .plus, "the pairing keeps a server in it")
    }

    /// The catalogue lever is the one that stayed pointed at a paid tier while
    /// nothing uses it: the seed leaves every technique free, because a session
    /// runs on the device and costs nobody anything. It is kept — and kept
    /// priced — for the day a technique does cost something to serve.
    @Test("The catalogue is priced but nothing is behind it")
    func theCatalogueLeverIsDormant() {
        #expect(SubscriptionTier.catalogue == .plus)
    }

    /// One subscription at two prices, and both prices have to buy it. A plan
    /// whose id fell out of this mapping presents as a genuine purchase that
    /// entitles nobody.
    @Test("Both cadences buy the one tier")
    func bothCadencesBuyPlus() {
        for plan in SubscriptionPlan.allCases {
            #expect(plan.tier == .plus, "\(plan)")
            #expect(
                SubscriptionTier.tier(forProductIdentifier: plan.productIdentifier) == .plus,
                "\(plan)"
            )
        }
    }

    /// A product id this build does not sell is a transaction to ignore rather
    /// than a person to downgrade, which is why the answer is `nil`.
    @Test("An unknown product buys no tier at all")
    func anUnknownProductBuysNothing() {
        #expect(SubscriptionTier.tier(forProductIdentifier: "xyz.holmie.ond.coach.monthly") == nil)
        #expect(SubscriptionPlan(productIdentifier: "") == nil)
    }

    /// The cached tier survives launches, and the three-tier build wrote a `2`
    /// into the same key. It has to read as free and be corrected by the first
    /// refresh, rather than crashing or promoting somebody.
    @Test("A tier from the old three-rung build reads as free")
    func aStaleCachedTierIsFree() {
        #expect(SubscriptionTier(rawValue: 2) == nil)
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

    /// The gate is a comparison, so paying never opens less.
    @Test("A locked technique opens at its tier and above")
    func lockedOpensAtItsTierAndAbove() {
        let locked = technique(requires: .plus)

        #expect(!locked.isUnlocked(for: .free))
        #expect(locked.isUnlocked(for: .plus))
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
