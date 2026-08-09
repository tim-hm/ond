import OndUI
import SwiftUI

/// Which home the Breathe tab is showing.
///
/// The two exist side by side so they can be felt against each other on a real
/// phone — a detent is not a thing anybody can judge from a screenshot or a
/// simulator. `HomeView`'s horizontal wheel survives for exactly as long as that
/// comparison is open; TIM-128 is closed by deleting one of them.
/// The raw value is what the switch draws, which is why the cases are the
/// lowercase words rather than something a `title` would have to translate.
enum HomeSurface: String, CaseIterable {
    /// The vertical dial: one recommended thing in focus, everything a tick
    /// away.
    case dial

    /// The horizontal aim wheel that shipped, and the orb under it.
    case wheel
}

/// The switch between the two homes, sat quietly in the corner of both.
///
/// The last of the prototype's scaffolding, and deliberately the smallest thing
/// that works: a control worth designing is a control somebody might keep.
struct HomeSurfaceSwitch: View {
    @Binding var surface: HomeSurface

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            ForEach(HomeSurface.allCases, id: \.self) { candidate in
                Button(candidate.rawValue) {
                    surface = candidate
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    candidate == surface ? Theme.Accent.brand : Theme.Ink.tertiary
                )
                .accessibilityAddTraits(candidate == surface ? [.isSelected] : [])
            }
        }
        .font(.caption)
        .padding(.horizontal, Theme.Spacing.close)
        .padding(.vertical, Theme.Spacing.tight)
        .glassCard()
        .padding(Theme.Spacing.standard)
        // Contained rather than merged, so the label names the pair and the two
        // buttons keep their own. A label on a stack that is not itself an
        // element propagates down instead, and VoiceOver then offers two
        // adjacent buttons both called "Home prototype".
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home prototype")
    }
}
