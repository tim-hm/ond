import OndKit
import OndStyle
import OndUI
import SwiftUI

/// What the phone shows while a discreet occasion is on its way to the wrist.
/// It replaces an alert that said "start it from OndWatch": the phone can now
/// deliver, so the same sentences are arranged as an outcome — with the old
/// copy kept verbatim for the case where nothing answers. Drawn as
/// `ContentUnavailableView`, the shape the rest of the app states this in.
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
                detail: "\(occasionTitle) runs with the screen off. The watch taps the rhythm."
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
                detail: "\(occasionTitle) runs with the screen off. The watch taps the rhythm. Start it from OndWatch."
            )
        case .locked:
            Copy(
                glyph: "applewatch",
                headline: "Send it to your watch",
                detail: "\(occasionTitle) runs with the screen off. The watch taps the rhythm. Starting it from OndWatch by hand is free; sending it from here is part of önd+."
            )
        }
    }
}
