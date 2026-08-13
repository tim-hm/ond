import Foundation
@testable import OndKit
import Testing

/// The names the leaderboard offers instead of asking somebody to invent one.
@Suite("Generated leaderboard names")
struct LeaderboardNameGeneratorTests {
    /// SplitMix64, which is four lines and repeats nothing — a generator that
    /// answered a fixed value would hang `randomElement(using:)`, whose
    /// rejection sampling asks again until it gets a number in range.
    private struct Seeded: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    private func name(seed: UInt64) -> String {
        var generator = Seeded(seed: seed)
        return LeaderboardNameGenerator.name(using: &generator)
    }

    @Test("The same seed gives the same name")
    func aSeededGeneratorIsDeterministic() {
        #expect(name(seed: 7) == name(seed: 7))
    }

    /// Not a claim about randomness — only that the generator is actually read.
    /// A `name()` that ignored it would pass every other test here.
    @Test("Different seeds give different names")
    func differentSeedsDiverge() {
        #expect(Set((0 ..< 32).map { name(seed: $0) }).count > 1)
    }

    /// Adjective, animal, two digits — the shape somebody reading a board
    /// recognises as generated rather than typed.
    @Test("Every name is adjective-animal-NN", arguments: 0 ..< 64 as Range<UInt64>)
    func theShapeHolds(_ seed: UInt64) throws {
        let parts = name(seed: seed).split(separator: "-")

        #expect(parts.count == 3)
        #expect(parts.prefix(2).allSatisfy { $0.allSatisfy(\.isLetter) })

        let suffix = try #require(Int(parts[2]))
        #expect(LeaderboardNameGenerator.suffixes.contains(suffix))
    }

    /// The alliteration is the whole charm of the shape, and it only survives
    /// because the words are written as pairs — two lists crossed would produce
    /// "puckly-otter" fifteen times out of sixteen.
    @Test("The two words alliterate")
    func theWordsAlliterate() {
        #expect(LeaderboardNameGenerator.pairs.allSatisfy { pair in
            pair.adjective.first == pair.animal.first
        })
    }

    /// A name that had to be trimmed would lose the digits that keep it
    /// distinct, and the trimmed version is what other people would then see.
    @Test("Every name fits the column, at the longest suffix")
    func everyNameFitsTheColumn() {
        let longest = LeaderboardNameGenerator.pairs.map { pair in
            "\(pair.adjective)-\(pair.animal)-\(LeaderboardNameGenerator.suffixes.upperBound)"
        }

        #expect(longest.allSatisfy { $0.unicodeScalars.count <= Profile.maxDisplayNameLength })
        #expect(longest.allSatisfy { $0.unicodeScalars.count >= Profile.minDisplayNameLength })
    }
}
