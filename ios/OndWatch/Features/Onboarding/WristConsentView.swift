import OndKit
import OndUI
import SwiftUI

/// The safety terms on the wrist, and the only screen a watch that has never
/// been asked can reach. The phone's wall in one scrolling column: the same
/// words, and the agreement on the button rather than beside it, because a
/// screen this size has room for one control and a checkbox before it would be
/// two taps for one decision. `docs/product/watch-consent.md` carries the rest.
struct WristConsentView: View {
    let store: SafetyConsentStore

    var body: some View {
        let terms = store.terms

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                header(terms)
                hazards(terms.points)
                agreement(terms.agreement)
            }
            .padding(.bottom, Theme.Spacing.close)
        }
    }

    private func header(_ terms: SafetyConsent) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            // One mark, not one per hazard: five identical triangles read as
            // decoration by the third. Hidden from VoiceOver because it says
            // nothing the title does not.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.Accent.caution)
                .accessibilityHidden(true)

            Text(terms.title)
                .displaySerif(size: 22)
                .foregroundStyle(Theme.Ink.primary)

            Text(terms.intro)
                .font(.caption2)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Hairline-separated, as the phone's wall has them: each hazard is a thing
    /// on its own to read and to hear, not a paragraph to skim.
    private func hazards(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Theme.Surface.line)

            ForEach(points.indices, id: \.self) { index in
                Text(points[index])
                    .font(.caption2)
                    .foregroundStyle(Theme.Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.close)

                Divider().overlay(Theme.Surface.line)
            }
        }
    }

    /// After the last hazard rather than pinned to the bottom edge: a button
    /// standing over the terms from the first frame is one offered before
    /// anything has been read.
    private func agreement(_ word: String) -> some View {
        Button {
            store.record()
        } label: {
            Text(word)
                .brandActionLabel()
                .padding(.vertical, Theme.Metrics.primaryActionInset)
                .background(Theme.Accent.brand, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
