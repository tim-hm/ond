import OndKit
import OndStyle
import OndUI
import SwiftUI

/// The session screen at rest: what is about to be practised, how long it
/// runs, and the two honest answers to being reminded of it.
///
/// "Not now" is as load-bearing as Begin. A reminder that can only be obeyed
/// is a reminder people turn off, and the way out of a full-screen cover is
/// otherwise a swipe nobody has been told about.
///
/// Its own file for the reason `HoldView` is: it exists for one entry — a
/// notification's — and the screen around it does not.
struct SessionInvitationView: View {
    let technique: Technique
    let onBegin: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.loose) {
            Spacer()

            VStack(spacing: Theme.Spacing.close) {
                Text(technique.name)
                    .font(.largeTitle.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(lengthLabel)
                    .font(.body)
            }

            Spacer()

            Button("Begin", action: onBegin)
                .buttonStyle(.capsuleAction(Theme.Accent.brand))

            Button("Not now", action: onDecline)
                .font(.subheadline)
                .frame(minHeight: 44)
        }
        .padding(Theme.Spacing.loose)
        // Primary is the only ink that clears AA over the accent wash, so there
        // is no tone left to spend on hierarchy here.
        .foregroundStyle(Theme.Ink.primary)
    }

    /// How long the session runs — "about" for a plan the clock owns, "around"
    /// for one whose holds the person ends.
    private var lengthLabel: String {
        let planned = technique.plannedDuration
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
        return technique.hasOpenEndedStage ? "Around \(planned)" : "About \(planned)"
    }
}
