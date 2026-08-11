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
    /// One breath, in seconds.
    public static let cycle = 3.0

    /// How full the lungs are, 0...1, at a point on a timeline's clock.
    public static func fullness(at time: TimeInterval) -> Double {
        let progress = time.truncatingRemainder(dividingBy: cycle) / cycle
        return 0.5 - 0.5 * cos(progress * 2 * .pi)
    }
}
