import SwiftUI

/// The app's name. Lowercase, and never uppercased — the name is önd, and ÖND
/// is a different word wearing its hat. Surfaces that set something else
/// beside the name build their own lockup: the watch pairs it with the clock,
/// and önd+ with a plus at its own baseline.
public struct Wordmark: View {
    public init() {}

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
            Text("önd")
                .displaySerif(size: 30)
                .foregroundStyle(Theme.Ink.primary)

            Text("breathe")
                .displaySerif(size: 17)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
