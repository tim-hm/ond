import Foundation

/// The stand-in wrist: readings invented for a machine that has none. Only a
/// Debug simulator's composition root ever routes here. It stands in for the
/// reading half alone: `begin()` skips the outbox's tier gate, the launch, the
/// ack and the order id, since none can succeed with no wrist. `rehearsal`,
/// `rehearsedArrivals`, `clock` and `take` are internal for this file alone.
extension PulseMonitor {
    /// Feeds the badge a settling heart, at the cadence a wrist would keep.
    /// Through `take` rather than straight onto the property, so the trace
    /// fills, the staleness timer runs, and an unchanged rate dedupes exactly
    /// as on hardware; `PulseRelay.spacing` because a livelier cadence would
    /// flatter it. Internal only for its one cross-file caller, `begin()`.
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

    /// Seventy-four settling into the high fifties, wobbling a beat or two — a
    /// heart doing what the practice is for. Arithmetic, not a random draw, so a
    /// screenshot taken twice shows the same session. Public because the badge's
    /// preview draws this curve too. `arrivals` is clamped rather than trusted:
    /// a negative index would trap in the wobble table rather than draw a heart.
    public static func rehearsedRate(after arrivals: Int) -> Int {
        let arrivals = max(0, arrivals)
        let wobble = [0, 2, -1, 1, -2, 1, 0, -1][arrivals % 8]
        return 74 - min(arrivals, 16) + wobble
    }
}
