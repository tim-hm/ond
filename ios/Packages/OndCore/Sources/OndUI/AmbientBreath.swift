import Foundation

/// The app's one idle breath, for the things that are alive on screen without
/// asking anything of anyone. Named once because two things breathing at
/// different rates read as two clocks. A cosine so the turn at full and at
/// empty is soft. The *session's* breath follows a technique's phases and
/// belongs to `BreathRhythm`; this is idle motion.
public enum AmbientBreath {
    /// One breath, in seconds — the stir of a dot that is merely alive.
    public static let cycle = 3.0

    /// One resting breath, in seconds: Coherent Breathing's 5.5 in and 5.5
    /// out, for the orb that breathes on Home. A literal rather than a read of
    /// the catalogue — this module must not learn about exercises — and
    /// `RestingBreathTests` keeps it equal to the seeded Coherent breath.
    public static let restingCycle = 11.0

    /// How full the lungs are, 0...1, at a point on a timeline's clock.
    ///
    /// - Parameter cycle: one breath's length in seconds; ``cycle`` unless the
    ///   surface is a resting breath rather than a stir.
    public static func fullness(at time: TimeInterval, cycle: Double = cycle) -> Double {
        let progress = time.truncatingRemainder(dividingBy: cycle) / cycle
        return 0.5 - 0.5 * cos(progress * 2 * .pi)
    }
}
