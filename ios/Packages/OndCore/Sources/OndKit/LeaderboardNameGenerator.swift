import Foundation

/// Names a person can be listed under without having to invent one:
/// "puckly-puffin-42".
///
/// The Ubuntu release-name shape — an adjective and an animal that start with
/// the same letter — because the boards are the one place in this app where a
/// stranger reads something about somebody, and the question "what do I want
/// strangers to call me" is a worse thing to meet than a name already in the
/// field. Offered as a default with a regenerate beside it; typing your own
/// still works, and an empty field still means invisible.
///
/// The suffix is what makes a collision unlikely rather than impossible. The
/// server holds a unique index on the column and answers a clash by suffixing
/// the name itself (`profile/repository.rs`), so a duplicate here costs somebody
/// a "-2" they did not choose rather than a refusal — which is why two digits is
/// enough and a longer number would only make the names worse to read.
///
/// Every name it can produce fits `Profile.maxDisplayNameLength`, which
/// `everyNameFitsTheColumn` pins: no pair here is long enough to be trimmed, and
/// a trimmed name would lose the digits that keep it distinct.
public enum LeaderboardNameGenerator {
    /// The pairs, keyed by the letter they alliterate on.
    ///
    /// Written as pairs rather than as two lists crossed, because the shape only
    /// works when both halves start alike — a free cross would produce
    /// "puckly-otter" fifteen times out of sixteen. Every word is one somebody
    /// would be happy to be called: nothing about size, nothing about ability,
    /// and no animal anybody uses as an insult.
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

    /// The same, from a generator the caller supplies.
    ///
    /// The seam the tests use: a seeded generator makes the format and the
    /// determinism assertable without either of them turning on what the system
    /// happened to roll. `inout some RandomNumberGenerator` rather than a
    /// concrete type, so a test's generator can be a three-line struct.
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
