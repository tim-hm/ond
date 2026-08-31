import Foundation

/// Facts about a body, mirrored from the `physiology` crate because Swift
/// cannot depend on a Cargo one. `catalogue.json` carries the number, and
/// `PhysiologyTests` asserts these constants against what the seed exported.
/// A constant rather than a value read from the export, so a broken download
/// is a failing test rather than a session missing its hint line.
public enum Physiology {
    /// Shorter than this, one breath in and out is over-breathing rather than
    /// breathing slowly. Four seconds a cycle is fifteen breaths a minute, the
    /// top of the usual resting range.
    public static let fastBreathingCycle = Duration.seconds(4)

    /// Whether a cycle this long counts as over-breathing. The comparison as
    /// well as the number mirrors `breathes_fast`: which side of the line the
    /// boundary falls on is what a second copy gets wrong.
    public static func breathesFast(_ cycle: Duration) -> Bool {
        cycle < fastBreathingCycle
    }
}

public extension Stage {
    /// Whether the whole cycle runs faster than a resting rate. Not
    /// [`isFastRhythm`] beside it, which asks whether a phase outruns its own
    /// count at two seconds; this asks whether a cycle outruns a resting rate
    /// at four, and the physiological sigh separates them. The whole cycle,
    /// holds included, is what the Rust rule takes.
    var breathesFast: Bool {
        Physiology.breathesFast(cycleDuration)
    }
}
