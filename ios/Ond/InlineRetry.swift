import OndUI
import SwiftUI

/// A failure inside a list section: one sentence and one way to ask again.
/// The section-sized counterpart to `ReferenceRetryView`: a failed section
/// leaves the rest of the screen working, and a centred
/// `ContentUnavailableView` draws badly inside one `Section`. Rows, not a
/// `VStack`, so the pieces inherit the list's own insets and separators.
struct InlineRetry: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.Ink.secondary)
        DebugHostNote()
        Button("Try again", action: retry)
            .font(.footnote)
    }
}
