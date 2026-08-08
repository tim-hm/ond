import OndUI
import SwiftUI
import UIKit

/// The anonymous id this install is filed under, and a tap that copies it.
///
/// Quiet on purpose, because almost nobody needs it: erasure has its own button
/// two rows down, and signing in makes a restore ask for nothing at all. The
/// person this exists for is local-only and writing in — no name, no email and
/// no account — for whom this id is the whole of the answer to "which record is
/// yours". So the row is labelled for that moment rather than for what the id
/// technically is, and somebody who does not need it can read the label and move
/// on rather than wonder.
///
/// Truncated in the middle rather than wrapped: an id is copied, not read, and a
/// row that grows to three lines makes a support detail look like a heading.
struct SupportIdentifierRow: View {
    let userId: UUID

    /// Whether the last tap copied. Reverted on a timer, because a tick that
    /// stays put stops meaning "just now" — and it is the only confirmation
    /// there is that the tap did anything.
    @State private var hasCopied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = userId.uuidString
            hasCopied = true

            Task {
                try? await Task.sleep(for: .seconds(2))
                hasCopied = false
            }
        } label: {
            LabeledContent("Support ID") {
                HStack(spacing: 6) {
                    Text(userId.uuidString)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(Theme.Accent.brand)
                }
            }
        }
        // Plain, for the reason the subscription row above is: the row's first
        // job is to state a fact, and only then to be tappable by whoever wants
        // the fact in their clipboard.
        .buttonStyle(.plain)
        .accessibilityLabel("Support ID")
        .accessibilityValue(userId.uuidString)
        .accessibilityHint("Copies your identifier")
    }
}
