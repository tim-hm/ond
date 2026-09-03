import OndUI
import SwiftUI

/// The wrist's waiting state, on the rule the phone's `ReferenceLoadingView`
/// set: no spinner, because one that flashes for a frame is noise rather than
/// news. Its own view rather than the phone's — that one leads with the
/// wordmark, and a watch screen has room for the sentence or the mark, not both.
struct WristLoadingView: View {
    var body: some View {
        Text("Loading…")
            .font(.caption2)
            .foregroundStyle(Theme.Ink.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
