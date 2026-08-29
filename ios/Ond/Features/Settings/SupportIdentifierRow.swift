import OndUI
import SwiftUI
import UIKit

/// The reference this install quotes when its owner writes in; a tap copies
/// it. A reference, never the identity itself: possession of the raw id is
/// the whole claim to the account, erasure included, so copying it under
/// "Support ID" invited mailing a bearer credential to a stranger.
/// `AccountModel.supportReference` derives the harmless value.
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
