import OndKit
import OndUI
import SwiftUI

/// The dial's one committing control.
///
/// The orb it replaces was a circle that breathed, cross-faded through the
/// goal's accent, and carried the word "begin" beneath it. On a real phone that
/// was the busiest thing on a screen whose whole argument is stillness — a
/// second ambience competing with the dial for the same glance, and a colour
/// change on every tick. What is left is the part that was doing the work: an
/// obvious, ordinary button, in the brand accent the rest of the app commits in,
/// which does not move until it is pressed.
///
/// The heavy tap is answered on the press rather than the release, which is what
/// makes a control feel like a button: the finger is told while it is still
/// down. It is the heaviest haptic on the screen because this is the only action
/// on it that cannot be undone by ticking somewhere else.
struct BeginButton: View {
    /// What is about to be started, for the label VoiceOver reads. The button
    /// itself says only "Begin" — the dial above it has just named the thing,
    /// and a button repeating it would be the screen saying it twice.
    let technique: Technique

    /// Whether a subscription owns this exercise, in which case pressing opens
    /// the paywall rather than a session. It changes nothing that is drawn — the
    /// focused row already carries the lock, and a second mark on the one
    /// control this screen has would be the screen arguing with itself — but
    /// VoiceOver is told, because "starts the session" would be a lie.
    let isLocked: Bool

    let action: () -> Void

    /// Bumped per press, purely so the haptic has something to fire on.
    @State private var presses = 0

    var body: some View {
        Button("Begin") {
            presses += 1
            action()
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .font(.headline)
        .accessibilityLabel("Begin \(technique.name)")
        .accessibilityHint(isLocked ? "Shows what önd Plus includes" : "Starts the session")
        .sensoryFeedback(.impact(weight: .heavy), trigger: presses)
    }
}
