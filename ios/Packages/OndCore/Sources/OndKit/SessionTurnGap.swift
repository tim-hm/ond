import Foundation

/// The beat of stillness that closes every scheduled phase, so the turn does
/// not read as a stumble. Borrowed from the phase, never inserted between
/// phases: inserting would lengthen every session and make the catalogue's
/// quoted doses lie. Sized by tempo from the phase's own length, not the
/// technique's slug. Every number the effect has is on this type.
public enum SessionTurnGap {
    /// The pause that makes a stacked breath read as a second movement rather
    /// than the tail of the first one.
    public static let stackedBreath: Duration = .milliseconds(200)

    /// The shortest pause that still reads as a pause. Below this the turn is
    /// back to being a corner, so a fast phase takes this rather than a
    /// proportional slice that would round away to nothing.
    public static let shortest: Duration = .milliseconds(25)

    /// The longest, which every calm phase from three seconds up reaches.
    /// Past it the guide reads as hesitating rather than arriving.
    public static let longest: Duration = .milliseconds(75)

    /// How much of a phase the gap takes between those two bounds. 2.5% puts
    /// bellows breathing's one-second phases on `shortest` and anything from
    /// three seconds up on `longest`, with a Wim Hof power breath's 1.5s
    /// landing between at 38 ms — a ramp rather than a step at a threshold.
    public static let share = 0.025

    /// The most of a phase the gap may take, whatever `shortest` asks for.
    /// Nothing curated comes near it, but a phase authored shorter than
    /// `shortest` would otherwise be all gap and no breath.
    public static let maximumShare = 0.1

    /// The most a stacked-breath pause may borrow from an unusually short
    /// phase. The shipped sighs reach the fixed 200 ms ceiling; this cap keeps
    /// custom sub-second phases predominantly breath rather than stillness.
    public static let maximumStackedShare = 0.2

    /// The bounds again as milliseconds, converted once:
    /// `Duration.milliseconds` decomposes a 128-bit attosecond count, and
    /// `Beat.breathing` asks on every frame. The `Duration` constants above
    /// stay the tuning surface.
    private static let shortestMilliseconds = Double(shortest.milliseconds)
    private static let longestMilliseconds = Double(longest.milliseconds)

    /// The stillness closing a phase of `duration`, in whole milliseconds —
    /// the ordinary tempo gap, unless `beforeStackedBreath` says another
    /// movement in the same direction follows and the larger, capped pause
    /// applies. A span of zero has no breath to borrow from.
    public static func length(
        ofPhase duration: Duration,
        beforeStackedBreath: Bool = false
    ) -> Duration {
        let span = Double(duration.milliseconds)
        let ordinary = min(
            max(span * share, shortestMilliseconds),
            longestMilliseconds,
            span * maximumShare
        )
        let gap = beforeStackedBreath
            ? max(ordinary, min(Double(stackedBreath.milliseconds), span * maximumStackedShare))
            : ordinary
        return .milliseconds(Int64(gap.rounded()))
    }
}
