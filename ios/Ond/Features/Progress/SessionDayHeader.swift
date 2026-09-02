import OndKit
import OndUI
import SwiftUI

/// The title row of one day's plate — `Today · 11 min`. It sits on the plate
/// rather than over the scroll, so it draws no ground of its own.
struct SessionDayHeader: View {
    let day: SessionDay

    var body: some View {
        Text("\(day.title) · \(day.minutes) min")
            .font(.caption)
            .foregroundStyle(Theme.Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.close)
            .accessibilityAddTraits(.isHeader)
    }
}
