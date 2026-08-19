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

    var body: some View {
        if presence.sessionEndsAt != nil || presence.sessionRemaining != nil {
            VStack(alignment: .trailing, spacing: 0) {
                time
                suffix
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var time: some View {
        if let sessionEndsAt = presence.sessionEndsAt {
            let now = Date.now
            if sessionEndsAt > now {
                Text(timerInterval: now ... sessionEndsAt, countsDown: true)
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
        }
    }
}
