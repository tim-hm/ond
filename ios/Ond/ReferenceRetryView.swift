import SwiftUI

/// The phone's reference-data failure state: one explanation and one route to
/// ask again.
///
/// App-local because Home, Exercises, and Foundations all use it, while the
/// watch deliberately keeps its own catalogue presentation.
struct ReferenceRetryView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
        }
    }
}
