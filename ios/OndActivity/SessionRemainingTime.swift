import OndKit
import SwiftUI

/// The whole session's remaining time, counted locally while the plan runs and
/// frozen while it is paused.
///
/// The Live Activity receives snapshots rather than frames. A wall-clock end is
/// therefore the running source of truth: `Text(timerInterval:)` advances in the
/// system process even when the app cannot push another update. Open-ended
/// plans draw no total because their end belongs to the person, not the clock.
struct SessionRemainingTime: View {
    let presence: SessionPresence
    var showsSuffix = false

    /// No accessibility container around this pair, deliberately, and the
    /// suffix hidden from VoiceOver instead of merged with the digits.
    ///
    /// `.accessibilityElement(children: .combine)` read better — "12:34 left" as
    /// one phrase — and stopped the clock. Combining obliges SwiftUI to resolve
    /// every child down to a concrete string to compose the merged label, and a
    /// widget renders out of process into an archive: once resolved, the timer
    /// is a dead string that redraws only when the next push lands. It cost the
    /// one number on this surface the system was keeping alive for free.
    ///
    /// So the timer below carries no modifier of its own, which is the condition
    /// for staying live, and VoiceOver reads "12:34" without the word. The phase
    /// and the technique name beside it already say what is being timed. The
    /// same trap took the retention count out of `SessionCueLabel` once — its
    /// `.accessibilityValue` is that fix.
    var body: some View {
        // `sessionRemaining` alone, because a payload carrying an end always
        // carries the remainder it was derived from: both come off the one
        // binding in `SessionPresence.init`.
        if presence.sessionRemaining != nil {
            VStack(alignment: .trailing, spacing: 0) {
                time
                suffix
            }
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private var time: some View {
        if let sessionEndsAt = presence.sessionEndsAt, let remaining = presence.sessionRemaining {
            if sessionEndsAt > .now {
                // The interval's lower bound is recovered from the payload
                // rather than stamped off this process's clock: only the upper
                // bound drives the count, and a bound read at render time makes
                // the interval depend on when WidgetKit evaluates this body.
                Text(
                    timerInterval: sessionEndsAt.addingTimeInterval(-remaining.seconds)
                        ... sessionEndsAt,
                    countsDown: true
                )
            } else {
                Text("0:00")
            }
        } else if let remaining = presence.sessionRemaining {
            Text(remaining.formatted(.time(pattern: .minuteSecond)))
        }
    }

    @ViewBuilder
    private var suffix: some View {
        if showsSuffix {
            Text("left")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
