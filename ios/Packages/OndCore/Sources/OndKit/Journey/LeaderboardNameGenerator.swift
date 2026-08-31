import Foundation

/// Names a person can be listed under without having to invent one:
/// "puckly-puffin-42" — the Ubuntu shape, so nobody meets "what do I want
/// strangers to call me". Collisions are the server's: its unique index
/// suffixes a clash, so a duplicate costs a "-2", not a refusal. Every name
/// fits `Profile.maxDisplayNameLength`; a trimmed one would lose its digits.
public enum LeaderboardNameGenerator {
    /// The pairs, keyed by the letter they alliterate on. Pairs rather than
    /// two lists crossed — a free cross would produce "puckly-otter" fifteen
    /// times out of sixteen. Every word is one somebody would be happy to be
    /// called: nothing about size or ability, no animal used as an insult.
    static let pairs: [(adjective: String, animal: String)] = [
        ("amber", "auk"),
        ("balmy", "bison"),
        ("brisk", "badger"),
        ("candid", "curlew"),
        ("calm", "crane"),
        ("dappled", "dormouse"),
        ("eager", "eider"),
        ("fluent", "finch"),
        ("gentle", "gannet"),
        ("golden", "grebe"),
        ("hushed", "heron"),
        ("idle", "ibis"),
        ("jaunty", "jackdaw"),
        ("keen", "kestrel"),
        ("lucid", "lapwing"),
        ("mellow", "marten"),
        ("nimble", "nuthatch"),
        ("open", "otter"),
        ("patient", "puffin"),
        ("puckly", "puffin"),
        ("quiet", "quail"),
        ("rested", "robin"),
        ("steady", "swift"),
        ("supple", "starling"),
        ("tidal", "teal"),
        ("upright", "urchin"),
        ("vivid", "vole"),
        ("willing", "wren"),
    ]

    /// The range the numeric suffix is drawn from — two digits, always two, so
    /// every generated name has the same shape and none of them reads as having
    /// been cut short.
    static let suffixes = 10 ... 99

    /// A fresh name, using the system's randomness.
    public static func name() -> String {
        var generator = SystemRandomNumberGenerator()
        return name(using: &generator)
    }

    /// The same, from a generator the caller supplies — the seam the tests
    /// use to assert the format deterministically. `inout some
    /// RandomNumberGenerator` so a test's generator can be a three-line struct.
    public static func name(using generator: inout some RandomNumberGenerator) -> String {
        // Force-unwrapped nowhere: `randomElement` is nil only for an empty
        // collection, and both of these are literals with entries in them —
        // stated as a fallback rather than a `!` so an emptied list degrades to
        // a name somebody can still edit rather than to a crash on the
        // leaderboard screen.
        let pair = pairs.randomElement(using: &generator) ?? ("quiet", "quail")
        let suffix = suffixes.randomElement(using: &generator) ?? suffixes.lowerBound

        return "\(pair.adjective)-\(pair.animal)-\(suffix)"
    }
}
