import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The orb, as the control that starts the session.
///
/// A circle with no chrome is the least discoverable thing an interface can
/// offer, so this is deliberately more than the circle: the word sits under it,
/// the pair is one accessibility element naming the exercise it will start, and
/// `Button` supplies the trait that tells VoiceOver it can be pressed. The
/// target is the stack's bounds, which are wider and taller than the orb's 176pt
/// frame.
///
/// The orb breathes in the goal's accent rather than the brand's, so the colour
/// answers the wheel above it.
///
/// What a press looks like is `AmbientOrb.Role`'s to decide; this view only
/// says which moment the orb is in. The tap is then held for
/// `AmbientOrb.acknowledgement` before the caller's action runs, so the ring
/// has time to leave: the screen's one committing action should be answered
/// before the screen changes rather than by the screen changing.
struct OrbBeginButton: View {
    let technique: Technique

    /// Whether a subscription owns this exercise, in which case pressing opens
    /// the paywall rather than a session. It changes nothing that is drawn —
    /// the aim above the orb already carries the lock, and a second mark on the
    /// one control this screen has would be the screen arguing with itself —
    /// but VoiceOver is told, because "starts the session" would be a lie.
    let isLocked: Bool

    /// How much the screen's width grows the type, 1 on the smallest phones.
    /// A multiplier on a Dynamic Type–scaled base, so the person's text setting
    /// still applies over the top.
    let typeScale: CGFloat

    let action: () -> Void

    /// `title3`'s size as a metric, so `typeScale` multiplies it without
    /// detaching the word from Dynamic Type. A step up from the `headline` it
    /// read at, and one step ahead of the aim word above the orb — the same
    /// gap in emphasis those two had before, at a size that carries an
    /// otherwise empty screen.
    @ScaledMetric(relativeTo: .title3) private var wordSize: CGFloat = 20

    /// The band the word sits in, matching the aim row's so the two words are
    /// equidistant from the orb whatever either one's line height is — which
    /// matching the gaps above and below alone would not achieve.
    @ScaledMetric(relativeTo: .body) private var band: CGFloat = 44

    /// Whether a finger is on the orb, reported up by `OrbPress` because a
    /// `ButtonStyle` is the only thing that knows.
    @State private var isPressed = false

    /// Whether the tap has been taken and the session is on its way.
    @State private var isTaken = false

    var body: some View {
        Button(action: take) {
            VStack(spacing: Theme.Spacing.loose) {
                AmbientOrb(accent: technique.goal.accent, role: role)

                // Lowercase to match the word row at the foot of the screen —
                // a visual choice, and the reason the accessibility label below
                // spells it as a proper sentence instead. VoiceOver reading
                // "begin box breathing" would sound like a fragment.
                Text("begin")
                    .font(.system(size: wordSize * typeScale, weight: .semibold))
                    .foregroundStyle(technique.goal.accent)
                    .frame(minHeight: band)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OrbPress(isPressed: $isPressed))
        .accessibilityLabel("Begin \(technique.name)")
        .accessibilityHint(
            isLocked ? "Shows what önd Plus includes" : "Starts the session"
        )
    }

    /// Which of the orb's moments this is. `taken` outranks `held` because the
    /// finger has already lifted by the time it is set.
    private var role: AmbientOrb.Role {
        if isTaken {
            .taken
        } else if isPressed {
            .held
        } else {
            .control
        }
    }

    /// Answers the tap before handing it on: the orb keeps the stillness the
    /// press put it in and its ring leaves, and only then does the session
    /// open. Guarded because the wait is long enough to be tapped into twice.
    private func take() {
        guard !isTaken else { return }
        isTaken = true

        Task {
            try? await Task.sleep(for: .seconds(AmbientOrb.acknowledgement))
            action()
            isTaken = false
        }
    }
}

/// The orb's press, which the orb itself draws.
///
/// A `ButtonStyle` is the only thing that knows when a finger is down, so this
/// one reports that upwards rather than acting on it. Everything a style could
/// do instead — a scale, a brightness — lands in a channel the orb's own breath
/// already occupies at more than twice the amplitude, so the answer to a press
/// lives in `AmbientOrb` where the breath is and can be stopped.
private struct OrbPress: ButtonStyle {
    /// Where the press is reported to. Written from `onChange` rather than the
    /// body below, which would be a write while rendering.
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
            // On the press rather than the release, which is what makes a
            // control feel like a button: the finger is answered while it is
            // still down. Heavier than the aim's step above it, because this is
            // the screen's one committing action.
            .sensoryFeedback(
                .impact(weight: .heavy),
                trigger: configuration.isPressed
            ) { _, pressed in
                pressed
            }
    }
}
