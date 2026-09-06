import SwiftUI

/// The phone's distinct successful-but-empty catalogue state.
///
/// Kept separate from `ReferenceRetryView` because an empty server answer is
/// not a connectivity failure, even though retrying is the useful next action
/// for both.
struct EmptyCatalogueView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Exercises aren’t available", systemImage: "wind")
        } description: {
            Text("We couldn’t load the exercises. Try again.")
        } actions: {
            Button("Try again", action: retry)
        }
    }
}
