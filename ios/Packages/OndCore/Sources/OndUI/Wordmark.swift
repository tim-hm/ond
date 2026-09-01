import SwiftUI

/// The app's name, set once. Two words rather than one string: they take
/// different sizes and different inks, and they align on the baseline they
/// share. Lowercase, and never uppercased — the name is önd, and ÖND is a
/// different word wearing its hat. Surfaces that draw something else beside
/// the name, like the watch's clock or önd+'s plus, build their own lockup.
public struct Wordmark: View {
    /// The size "önd" is set at. The second word derives from it, so a surface
    /// states one number and the pair keeps its proportion.
    private let size: CGFloat

    /// What "breathe" takes of the name's size. The ratio Home was drawn at.
    private static let secondWord: CGFloat = 0.57

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
            Text("önd")
                .displaySerif(size: size)
                .foregroundStyle(Theme.Ink.primary)

            Text("breathe")
                .displaySerif(size: size * Self.secondWord)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
