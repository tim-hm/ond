import Foundation

/// The beat of stillness that closes every scheduled phase: the lungs held
/// where they arrived, nothing new asked, and then the next phase.
///
/// A guide whose envelope runs right up to the boundary turns on a corner — the
/// countdown reads 1, the orb tops out, and the exhale is already under way in
/// the same frame. There is no headroom in that, and the seam reads as a
/// stumble rather than a turn. What this buys back is a few tens of
/// milliseconds of arrival before the reversal.
///
/// **Borrowed from the phase, not added between phases.** A beat keeps the
/// authored `[start, end)` it has always had and stops *moving*
/// `length(ofPhase:)` early, so the next phase still begins exactly on
/// schedule. Inserting the pause instead — every beat's span becoming breath
/// plus gap — is the more literal reading of "a delay between the steps" and
/// feels identical, because either way the person gets exactly this long of
/// stillness before the next cue arrives. What it also does is lengthen every
/// session: cyclic sighing's thirty ten-second cycles would run 5m04s, against
/// a catalogue entry that calls its five minutes the dose the trial ran, and
/// `Technique.plannedDuration`, the Customise dials and the marketing site's
/// figures would all go on quoting a session the app no longer plays. Only one
/// of the two placements makes the catalogue lie, so the pause comes out of the
/// breath.
///
/// **Sized by tempo, from the phase's own length.** A bellows breath and a
/// four-second inhale cannot share a pause: what reads as a turn at one pace
/// reads as a stall at the other. Derived from the duration rather than from
/// the technique's slug, on `Stage.isFastRhythm`'s argument — tempo is a fact
/// about the phase in front of you, and a phase dialled down to the bottom of
/// its range is a fast phase whatever exercise it belongs to.
///
/// Every number the effect has is on this type. Tuning how it feels is an edit
/// here and nowhere else.
public enum SessionTurnGap {
    /// The shortest pause that still reads as a pause. Below this the turn is
    /// back to being a corner, so a fast phase takes this rather than a
    /// proportional slice that would round away to nothing.
    public static let shortest: Duration = .milliseconds(25)

    /// The longest, which every calm phase from three seconds up reaches.
    /// Past it the guide reads as hesitating rather than arriving.
    public static let longest: Duration = .milliseconds(75)

    /// How much of a phase the gap takes between those two bounds.
    ///
    /// 2.5% puts bellows breathing's one-second phases on `shortest` and
    /// anything from three seconds up on `longest`, with a Wim Hof power
    /// breath's 1.5s landing between the two at 38 ms — which is the ramp the
    /// band exists for, rather than a step at some threshold.
    public static let share = 0.025

    /// The most of a phase the gap may take, whatever `shortest` asks for.
    ///
    /// Nothing curated comes near it — the shortest dialled phase in the
    /// catalogue is the sigh's 500 ms sip, which gives up 5% — but a phase
    /// authored shorter than `shortest` would otherwise be all gap and no
    /// breath.
    public static let maximumShare = 0.1

    /// The bounds again as milliseconds, converted once.
    ///
    /// `Duration.milliseconds` decomposes a 128-bit attosecond count, and
    /// `Beat.breathing` asks for this on every frame of every session. The
    /// `Duration` constants above stay the tuning surface; these are the same
    /// two numbers in the units the arithmetic runs in.
    private static let shortestMilliseconds = Double(shortest.milliseconds)
    private static let longestMilliseconds = Double(longest.milliseconds)

    /// The stillness closing a phase of `duration`.
    ///
    /// - Parameter duration: the phase's authored span. A span of zero has no
    ///   breath to borrow from, and `maximumShare` returns it unchanged.
    /// - Returns: whole milliseconds, never more than a tenth of the phase.
    public static func length(ofPhase duration: Duration) -> Duration {
        let span = Double(duration.milliseconds)
        let gap = min(
            max(span * share, shortestMilliseconds),
            longestMilliseconds,
            span * maximumShare
        )
        return .milliseconds(Int64(gap.rounded()))
    }
}
