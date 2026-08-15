import Foundation

/// The stand-in wrist: readings invented for a machine that has none.
///
/// Split from the body of ``PulseMonitor`` because it is the one part of that
/// type no shipped launch reaches — the composition root decides which builds
/// may rehearse, and the answer outside a Debug simulator is never. Keeping it
/// here means the arrangement itself reads as what it is, and this file is the
/// whole of what a reader has to hold in mind to know what a rehearsed session
/// is and is not.
///
/// What it stands in for is only the reading half. Everything a real arrangement
/// does first — the outbox's tier gate, waking the watch app, the ack, and the
/// order id every reading is measured against — is skipped by `begin()` on the
/// way here, because none of it can succeed with no wrist to answer.
///
/// The four members it reaches on the class — `rehearsal`, `rehearsedArrivals`,
/// `clock` and `take` — are internal rather than private for this file alone.
/// Nothing outside the module can see them, and nothing else inside it should.
extension PulseMonitor {
    /// Feeds the badge a settling heart, at the cadence a wrist would keep.
    ///
    /// Through `take` rather than straight onto the property, so the half it does
    /// stand in for is honest: the trace fills, the staleness timer runs, and an
    /// unchanged rate is deduped exactly as it is on hardware. `PulseRelay.spacing`
    /// for the same reason — a reading every eight seconds is part of what this
    /// looks like, and a livelier one would flatter it.
    ///
    /// Internal rather than private only because it lives across a file from its
    /// one caller. Nothing outside this module can reach it, and nothing inside
    /// should: `begin()` is where the decision belongs.
    func rehearse() {
        guard rehearsal == nil else { return }

        rehearsal = Task { [weak self] in
            while !Task.isCancelled, let self {
                take(Self.rehearsedRate(after: rehearsedArrivals))
                rehearsedArrivals += 1
                try? await clock.sleep(until: clock.now.advanced(by: PulseRelay.spacing))
            }
        }
    }

    /// Seventy-four settling into the high fifties over a couple of minutes,
    /// wobbling a beat or two on the way — a heart doing what the practice is
    /// for. Arithmetic rather than a random draw, so the same screenshot taken
    /// twice shows the same session.
    ///
    /// Public because the badge's own preview draws this curve too, and two
    /// invented hearts that disagreed would be a preview showing what no
    /// simulator ever will.
    ///
    /// - Parameter arrivals: how many readings have already landed. Clamped
    ///   rather than trusted, because the preview counts these off a clock and a
    ///   negative index would trap in the wobble table rather than draw a heart.
    public static func rehearsedRate(after arrivals: Int) -> Int {
        let arrivals = max(0, arrivals)
        let wobble = [0, 2, -1, 1, -2, 1, 0, -1][arrivals % 8]
        return 74 - min(arrivals, 16) + wobble
    }
}
