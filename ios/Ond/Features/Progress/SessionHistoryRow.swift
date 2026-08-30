import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One past session under its day's header: what it was, what time it started,
/// and how long it ran. The day is named above the row, so the row states only
/// the hour. An exercise gone from the catalogue takes the neutral vapour, not
/// a guess — a colour is a claim about what the session was for.
struct SessionHistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let record: SessionRecord
    let name: String

    /// What the session was for, or nil where its exercise is gone.
    let goal: TechniqueGoal?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.close) {
            dot

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
        }
        .padding(.vertical, Theme.Spacing.close)
        // `.ignore` with a label of its own rather than `.combine`: combine's
        // union frame spans the Spacer-split row — three foregrounds and bare
        // ground — and the accessibility audit measures contrast over exactly
        // that node, reporting a failure no single pairing here can account
        // for. Every pairing clears AA measured on its own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// The one mark the goal makes on the row. An ending by hand takes the
    /// neutral vapour instead: the row already says it stopped, and a goal
    /// accent there would colour it like practice that ran its course.
    private var dot: some View {
        Circle()
            .fill(mark)
            .frame(width: 6, height: 6)
            // Nudged down off the text baseline it is aligned to, so it sits
            // against the middle of the name rather than under it.
            .alignmentGuide(.firstTextBaseline) { $0.height }
            .accessibilityHidden(true)
    }

    private var mark: Color {
        guard record.completed, let goal else {
            return Theme.Breath.exhale.opacity(0.30)
        }
        return goal.accent
    }

    private var horizontal: some View {
        HStack(alignment: .firstTextBaseline) {
            title
            Spacer()
            stamp
        }
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            title
            stamp
        }
    }

    private var title: some View {
        Text(name)
            .font(.body)
            .foregroundStyle(Theme.Ink.primary)
    }

    private var stamp: some View {
        Text(stampLine)
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.Ink.secondary)
    }

    /// `08:10 · 5:00`, and `08:10 · stopped 1:12` where the person ended it by
    /// hand. The length is what was breathed either way: `SessionRecord` never
    /// carries the plan it fell short of.
    private var stampLine: String {
        let clock = record.startedAt.formatted(.dateTime.hour().minute())
        let length = record.duration.formatted(.time(pattern: .minuteSecond))

        return record.completed ? "\(clock) · \(length)" : "\(clock) · stopped \(length)"
    }

    /// The row as one sentence. Spoken in words rather than in the printed
    /// separators, which read as punctuation nobody wrote.
    private var spokenLabel: String {
        let clock = record.startedAt.formatted(date: .omitted, time: .shortened)
        let length = record.duration
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))

        return record.completed
            ? "\(name), \(clock), \(length)"
            : "\(name), \(clock), stopped after \(length)"
    }
}
