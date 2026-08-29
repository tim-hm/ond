import Foundation

/// The app's one idle breath, for the things that are alive on screen without
/// asking anything of anyone.
///
/// Named once because more than one screen draws something breathing at it —
/// the onboarding orb, the coach's thinking dot — and two things breathing at
/// different rates read as two clocks. A cosine rather than a ramp so the turn
/// at full and at empty is soft, the same reason the session orb smoothsteps.
///
/// Nothing here is the *session's* breath, which follows a technique's phases
/// and belongs to `BreathRhythm`. This is idle motion, and its only number is
/// how long one of them takes.
public enum AmbientBreath {
    /// One breath, in seconds — the stir of a dot that is merely alive.
    public static let cycle = 3.0

    /// One resting breath, in seconds: Coherent Breathing's 5.5 in and 5.5
    /// out, for the orb that breathes on Home while nobody is asked to follow
    /// it. A pace someone could fall into rather than a pulse.
    ///
    /// A number rather than a read of the catalogue, because this module knows
    /// nothing of exercises and must not learn. `RestingBreathTests` is what
    /// keeps it equal to the seeded Coherent breath.
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
