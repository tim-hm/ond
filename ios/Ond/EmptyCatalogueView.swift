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
            Label("The catalogue is empty", systemImage: "wind")
        } description: {
            Text("The server answered, but with no exercises in it.")
        } actions: {
            Button("Try again", action: retry)
        }
    }
}
