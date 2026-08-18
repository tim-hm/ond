import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What the phone shows while a discreet occasion is on its way to the wrist.
///
/// The screen this replaces was an alert that said "start it from OndWatch" and
/// left. Its honesty was the only thing to recommend it: the phone genuinely
/// could not deliver a discreet session, so it named the device that could. It
/// can now, and this sheet is the same three sentences arranged as an outcome
/// rather than an apology — with the old copy kept verbatim for the case where
/// nothing answers, because there the alert was simply right.
///
/// Drawn as `ContentUnavailableView`, which is the shape the rest of the app
/// states this kind of thing in, so the type sizes and the centring are the
/// platform's rather than this file's.
struct WristHandoffSheet: View {
    let occasionTitle: String
    let phase: WristLaunchModel.Phase
    let done: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(copy.headline, systemImage: copy.glyph)
        } description: {
            Text(copy.detail)
        } actions: {
            if phase == .sending {
                ProgressView()
            }

            if phase == .locked {
                UpgradePrompt(reason: "Sending a session to your wrist is part of", for: .watch)
            }

            Button(phase == .sending ? "Cancel" : "OK", action: done)
                .buttonStyle(.inkAction)
        }
        .paletteGround()
        .presentationDetents([.medium])
    }

    /// What the screen says, in one value.
    private struct Copy {
        let glyph: String
        let headline: String
        let detail: String
    }

    /// One mapping from the phase to everything the screen says, rather than a
    /// switch per line: three switches over the same enum are three places to
    /// forget a case, and nothing keeps them aligned.
    private var copy: Copy {
        switch phase {
        case .sending:
            Copy(
                glyph: "applewatch.radiowaves.left.and.right",
                headline: "Sending to your wrist…",
                detail: "\(occasionTitle) is meant to go unnoticed — no screen, just the rhythm tapped out."
            )
        case .running:
            Copy(
                glyph: "applewatch",
                headline: "Running on your wrist",
                detail: "Put your phone away. Your watch will tap the rhythm; nothing will appear on screen."
            )
        case .failed:
            Copy(
                glyph: "applewatch.slash",
                headline: "This one runs on your wrist",
                detail: "\(occasionTitle) is meant to go unnoticed — no screen, just the rhythm tapped out. Start it from OndWatch."
            )
        case .locked:
            Copy(
                glyph: "applewatch",
                headline: "Send it to your watch",
                detail: "\(occasionTitle) is meant to go unnoticed — no screen, just the rhythm tapped out. Starting it from OndWatch by hand is free; sending it from here is part of önd+."
            )
        }
    }
}
