import OndKit
import OndUI
import SwiftUI

/// One past session: what it was, how long it ran, and when.
struct SessionHistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let record: SessionRecord
    let name: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                vertical
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontal
                    vertical
                }
            }
        }
        .padding(.vertical, Theme.Spacing.tight)
        .accessibilityElement(children: .combine)
    }

    private var horizontal: some View {
        HStack(alignment: .firstTextBaseline) {
            session
            Spacer()
            timestamp
        }
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            session
            timestamp
        }
    }

    private var session: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(name)
                .font(.headline)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
    }

    private var timestamp: some View {
        Text(
            record.startedAt,
            format: Date.FormatStyle(date: .abbreviated, time: .shortened)
        )
        .font(.caption)
        .foregroundStyle(Theme.Ink.secondary)
    }

    /// Completion is the normal case; only an early ending adds qualification.
    private var detail: String {
        let length = record.duration
            .formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
        let cycles = record.cyclesCompleted == 1 ? "1 cycle" : "\(record.cyclesCompleted) cycles"

        var parts = [length, cycles]
        if !record.completed {
            parts.append("ended early")
        }
        return parts.joined(separator: " · ")
    }
}
