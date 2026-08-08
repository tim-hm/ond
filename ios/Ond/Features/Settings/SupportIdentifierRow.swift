import OndUI
import SwiftUI
import UIKit

/// The reference this install quotes when its owner writes in, and a tap that
/// copies it.
///
/// Quiet on purpose, because almost nobody needs it: erasure has its own button
/// two rows down, and signing in makes a restore ask for nothing at all. The
/// person this exists for is local-only and writing in — no name, no email and
/// no account — for whom this is the whole of the answer to "which record is
/// yours". So the row is labelled for that moment rather than for what the value
/// technically is.
///
/// **A reference, never the identity itself.** `AccountModel.supportReference`
/// is what makes that true and says why: possession of the id is the whole claim
/// to the account, erasure included, so a row that copied it to the pasteboard
/// under the words "Support ID" was inviting a person to mail a bearer
/// credential to a stranger. Twelve hex characters still find the row and
/// authorise nothing, which is what the label always promised.
struct SupportIdentifierRow: View {
    let reference: String

    /// Whether the last tap copied. Reverted on a timer, because a tick that
    /// stays put stops meaning "just now" — and it is the only confirmation
    /// there is that the tap did anything.
    @State private var hasCopied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = reference
            hasCopied = true

            Task {
                try? await Task.sleep(for: .seconds(2))
                hasCopied = false
            }
        } label: {
            LabeledContent("Support ID") {
                HStack(spacing: 6) {
                    Text(reference)
                        .lineLimit(1)

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
        .accessibilityValue(reference)
        .accessibilityHint("Copies your support reference")
    }
}
