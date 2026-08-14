import OndUI
import SwiftUI

/// A compact way into a secondary room, shared wherever navigation sits above
/// a screen's main content.
///
/// Progress and Coach both use these links as shortcuts rather than content:
/// the intrinsic glass capsule keeps that distinction visible and prevents the
/// same navigation role drifting into a full-width card on one tab.
struct ShortcutLink<Destination: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label {
                Text(title)
                    .foregroundStyle(Theme.Ink.primary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Accent.brand)
            }
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}
