import OndKit
import SwiftUI

/// The whole session's remaining time, counted locally while the plan runs and
/// frozen while it is paused.
///
/// The Live Activity receives snapshots rather than frames. A wall-clock window
/// is therefore the running source of truth: `Text(timerInterval:)` advances in
/// the system process even when the app cannot push another update. Open-ended
/// plans draw no total because their end belongs to the person, not the clock.
struct SessionRemainingTime: View {
    let presence: SessionPresence
    var showsSuffix = false

    var body: some View {
        // `sessionRemaining` alone: a payload carrying a window always carries
        // the remainder it was measured from, which `sessionWindow` states.
        if presence.sessionRemaining != nil {
            VStack(alignment: .trailing, spacing: 0) {
                time
                suffix
            }
            .monospacedDigit()
        }
    }

    /// No accessibility container around this pair, and no modifier on the
    /// timer below — which is the condition for it staying live.
    ///
    /// `.accessibilityElement(children: .combine)` read better, "12:34 left" as
    /// one phrase, and stopped the clock: combining obliges SwiftUI to resolve
    /// each child down to a concrete string to compose the merged label, and a
    /// widget renders out of process into an archive, so the resolved timer was
    /// a dead string that redrew only when the next push landed. It cost the
    /// one number here the system was keeping alive for free. `ios/.swiftlint.yml`
    /// holds the rule now, because a doc cannot protect the next file.
    @ViewBuilder
    private var time: some View {
        if let window = presence.sessionWindow {
            Text(timerInterval: window, countsDown: true)
        } else if let remaining = presence.sessionRemaining {
            Text(remaining.formatted(.time(pattern: .minuteSecond)))
        }
    }

    /// Hidden rather than merged with the digits, for the reason on ``time``.
    /// VoiceOver reads "12:34" without the word; the phase and the technique
    /// name beside it already say what is being timed.
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
