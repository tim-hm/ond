import OndUI
import SwiftUI

/// Which home the Breathe tab is showing.
///
/// The two exist side by side so they can be felt against each other on a real
/// phone — a detent is not a thing anybody can judge from a screenshot or a
/// simulator. `HomeView`'s horizontal wheel survives for exactly as long as that
/// comparison is open; TIM-128 is closed by deleting one of them.
enum HomeSurface: String, CaseIterable, Identifiable {
    /// The vertical dial: one recommended thing in focus, everything a tick
    /// away.
    case dial

    /// The horizontal aim wheel that shipped, and the orb under it.
    case wheel

    var id: Self {
        self
    }

    var title: String {
        rawValue
    }
}

/// The switch between the two homes, sat quietly in the corner of both.
///
/// Prototype scaffolding, and deliberately the smallest thing that works: a
/// control worth designing is a control somebody might keep.
struct HomeSurfaceSwitch: View {
    @Binding var surface: HomeSurface

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            ForEach(HomeSurface.allCases) { candidate in
                Button(candidate.title) {
                    surface = candidate
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(
                    candidate == surface ? Theme.Accent.brand : Theme.Ink.tertiary
                )
                .accessibilityAddTraits(candidate == surface ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, Theme.Spacing.close)
        .padding(.vertical, Theme.Spacing.tight)
        .glassCard()
        .padding(Theme.Spacing.standard)
        .accessibilityLabel("Home prototype")
    }
}
