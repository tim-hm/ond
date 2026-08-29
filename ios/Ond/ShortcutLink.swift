import OndUI
import SwiftUI

/// A compact way into a secondary room, shared wherever navigation sits above
/// a screen's main content. The intrinsic glass capsule keeps the shortcut
/// role visible and stops it drifting into a full-width card on one tab.
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
