import OndUI
import SwiftUI

/// The line under a tab's large title, saying which axis that screen sorts by.
/// A tab name is one word and cannot carry the distinction on its own —
/// Moments and Exercises are when and what, and neither name says so. Carries
/// its own page margin because the stacks that hold it pad their children
/// rather than themselves.
struct ScreenSubtitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.standard)
    }
}
