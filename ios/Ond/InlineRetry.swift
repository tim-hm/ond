import OndUI
import SwiftUI

/// A failure inside a list section: one sentence and one way to ask again.
///
/// The section-sized counterpart to `ReferenceRetryView`, which is screen-sized.
/// Both exist because the two failures are not the same event — a catalogue that
/// will not load leaves nothing to show, while a section that will not load
/// leaves the rest of the screen working — and a `ContentUnavailableView`
/// centred inside one `Section` of a `List` draws neither well.
///
/// Rows rather than a `VStack`, so the sentence and the button inherit the list's
/// own insets and separators instead of restating them.
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
