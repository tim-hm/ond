import Foundation

/// Chooses which session changes deserve a Live Activity redraw.
/// Slow breathing keeps phase-by-phase guidance; a rapid stage crosses phases
/// every second, so its redraws are reserved for stage seams, holds, and
/// explicit control changes. The latest state is retained even when a redraw
/// is skipped, so leaving a rapid hold publishes the arriving breath.
struct SessionActivityUpdatePolicy {
    private var status: SessionModel.Status
    private var beat: SessionTimeline.Beat?

    init(status: SessionModel.Status, beat: SessionTimeline.Beat?) {
        self.status = status
        self.beat = beat
    }

    mutating func shouldPublish(
        status nextStatus: SessionModel.Status,
        beat nextBeat: SessionTimeline.Beat?
    ) -> Bool {
        let statusChanged = nextStatus != status
        let beatChanged = nextBeat?.id != beat?.id
        let previousBeat = beat

        status = nextStatus
        beat = nextBeat

        guard statusChanged || beatChanged else { return false }
        guard !statusChanged else { return true }
        guard beatChanged, let nextBeat else { return true }
        guard nextBeat.isFastRhythm else { return true }

        return nextBeat.opensStage
            || nextBeat.kind.isHold
            || previousBeat?.kind.isHold == true
    }
}
