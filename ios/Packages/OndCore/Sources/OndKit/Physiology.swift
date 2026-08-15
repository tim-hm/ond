import Foundation

/// Facts about a body, mirrored from the `physiology` crate because Swift cannot
/// depend on a Cargo one.
///
/// That crate exists to abolish exactly this. `migrate` and `api` each held a
/// copy of the blackout rule's numbers, pinned by a test whose only job was to
/// watch them drift, and a leaf dependency with nothing in it was cheaper than
/// the test. No such dependency crosses a language boundary, so the number rides
/// the one artefact that already does — `catalogue.json` carries it, and
/// `PhysiologyTests` asserts this constant against what the seed exported. That
/// assertion is the drift test the crate deleted, restored at the one boundary
/// where it is still the only option.
///
/// A constant rather than a value read out of the export, deliberately. The
/// threshold is asked for while laying out a timeline, where threading a decoded
/// catalogue through would put a failed download between somebody and a hint
/// line. Keeping it compiled in means a broken export is a failing test rather
/// than a session missing its words.
public enum Physiology {
    /// Shorter than this, one breath in and out is over-breathing rather than
    /// breathing slowly. Four seconds a cycle is fifteen breaths a minute, the
    /// top of the usual resting range.
    public static let fastBreathingCycle = Duration.seconds(4)

    /// Whether a cycle this long counts as over-breathing.
    ///
    /// The comparison as well as the number, mirroring `breathes_fast`: which
    /// side of the line the boundary falls on is what a second copy gets wrong,
    /// and a rule that quietly stopped applying at its own threshold would look
    /// identical to one that worked.
    public static func breathesFast(_ cycle: Duration) -> Bool {
        cycle < fastBreathingCycle
    }

    /// The same numbers as the seed exported them, for the one test that
    /// compares the two.
    ///
    /// A type rather than a loose `Duration` so that a second mirrored fact —
    /// the timed-hold ceiling is the obvious next one — has somewhere to go
    /// without the comparison having to be rewritten around it.
    public struct Exported: Sendable, Hashable {
        public let fastBreathingCycle: Duration

        public init(fastBreathingCycle: Duration) {
            self.fastBreathingCycle = fastBreathingCycle
        }

        /// What an unreadable export degrades to: this build's own constants,
        /// which keeps `Bundled.empty` self-consistent and makes it useless as
        /// evidence that anything was read. The drift test says so.
        public static let compiledIn = Self(fastBreathingCycle: Physiology.fastBreathingCycle)
    }
}

public extension Stage {
    /// Whether the whole cycle runs faster than a resting rate.
    ///
    /// Deliberately not [`isFastRhythm`], which sits beside this and answers a
    /// different question. That one asks whether a *phase* outruns its own count,
    /// at two seconds; this asks whether a *cycle* outruns a resting rate, at
    /// four. The physiological sigh separates them — a one-second sip inside a
    /// 7.5-second cycle — and "Fast and even" printed over a sigh is the mistake
    /// that reusing the other property makes.
    ///
    /// The whole cycle, holds included, is what the Rust rule takes and what
    /// `cycleDuration` gives: one quick breath every forty seconds accumulates
    /// carbon dioxide rather than washing it out.
    var breathesFast: Bool {
        Physiology.breathesFast(cycleDuration)
    }
}
