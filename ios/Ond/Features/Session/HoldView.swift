import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The retention: the one phase with no end anybody knows in advance.
///
/// Nothing counts down here, because nothing knows how long this is — the timer
/// counts up, and the button is the only thing that ends it. What the round
/// suggests aiming for is stated under the count, and that is all it is: no
/// record, no maximum, and nothing that treats a shorter hold as a miss. A
/// maximal hold is still the one thing this app will not ask anyone for.
///
/// Its own file rather than a computed property on `SessionView` because it
/// exists for one protocol — Wim Hof's — and the screen around it does not.
struct HoldView: View {
    let model: SessionModel

    @Environment(SessionSettings.self) private var settings

    /// A second a tick, not a frame a tick: inside a hold the plan is frozen, so
    /// the orb holds still and the only thing moving on this screen is a timer
    /// counting whole seconds.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: Theme.Spacing.loose) {
                BreathVisual(
                    beat: model.currentBeat,
                    elapsed: model.elapsed,
                    timeline: model.timeline,
                    accent: model.accent,
                    register: model.timeline.register
                )
                .accessibilityHidden(true)

                VStack(spacing: Theme.Spacing.close) {
                    // The timer stays under Just the visuals — inside a hold
                    // the orb is frozen, so it is the only feedback there is.
                    if settings.guidance == .full {
                        Text(model.currentBeat?.instruction ?? "")
                            .font(.title2.weight(.medium))
                    }
                    Text(model.holdElapsed.formatted(.time(pattern: .minuteSecond)))
                        .font(.system(.largeTitle, design: .rounded).weight(.light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Ink.secondary)

                    if let aim {
                        Text(aim)
                            .font(.footnote)
                            .foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                // Explicit label and value rather than combined children, so
                // VoiceOver reads "Hold, lungs empty — 1:23" at every guidance
                // level, including the one that hides the instruction text.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.currentBeat?.spokenInstruction ?? "")
                .accessibilityValue(spokenValue)

                Button("I'm ready") {
                    model.release()
                }
                .font(.headline)
                .padding(.horizontal, Theme.Spacing.loose)
                .padding(.vertical, Theme.Spacing.close)
                .background(.thinMaterial, in: Capsule())
                .disabled(model.status != .holding)
                .accessibilityHint("Ends the hold and takes the recovery breath")
            }
        }
    }

    /// What this round asks for, in the calmest words the screen can put it in —
    /// and, once the time is behind them, an invitation to stop rather than a
    /// prompt to keep going.
    private var aim: String? {
        guard let target = model.currentBeat?.target else { return nil }

        let length = target.formatted(.time(pattern: .minuteSecond))
        return model.holdElapsed >= target
            ? "Past \(length) — end whenever you like"
            : "Aim for \(length)"
    }

    /// The count, and the aim after it, as one phrase — the aim is a `Text` of
    /// its own on screen, and the element around both is read as a single value.
    private var spokenValue: String {
        let count = model.holdElapsed.formatted(.time(pattern: .minuteSecond))
        return aim.map { "\(count), \($0)" } ?? count
    }
}
