import SwiftUI

/// The short rule that stands over a safety screen's title — the wall, and an
/// exercise's own caution. A rule and not a warning glyph: a triangle over a
/// page of warnings states the obvious twice, and it says nothing a screen
/// reader can use. One recipe because three screens draw it, on two devices,
/// and the wrist's is shorter only because its title is.
public struct CautionRule: View {
    private let width: CGFloat

    /// - Parameter width: how far it runs. Defaults to the wrist's.
    public init(width: CGFloat = 32) {
        self.width = width
    }

    /// No bottom inset: the gap to the title belongs to the screen's own
    /// stack, and the two that draw this stand at different scales.
    public var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Theme.Accent.caution)
            .frame(width: width, height: 2)
    }
}
