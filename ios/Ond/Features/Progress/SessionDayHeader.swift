import OndKit
import OndUI
import SwiftUI

/// The line over one day's sessions — `Today · 11 min`. It sticks to the top
/// of the scroll on the way past, so it carries an opaque ground of its own:
/// the rows would otherwise run under a transparent header.
struct SessionDayHeader: View {
    let day: SessionDay

    var body: some View {
        Text("\(day.title()) · \(day.minutes) min")
            .font(.caption)
            .foregroundStyle(Theme.Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, Theme.Spacing.close)
            .background(Theme.Surface.ground)
            .accessibilityAddTraits(.isHeader)
    }
}
