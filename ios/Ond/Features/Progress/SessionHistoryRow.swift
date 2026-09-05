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

    /// The hour the row prints, hoisted so a lazily built list does not
    /// construct the style once a row.
    private static let clock = Date.FormatStyle(date: .omitted, time: .shortened)

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

    private var dot: some View {
        Circle()
            .fill(mark)
            .frame(width: 6, height: 6)
            // Nudged down off the text baseline it is aligned to, so it sits
            // against the middle of the name rather than under it.
            .alignmentGuide(.firstTextBaseline) { $0.height }
            .accessibilityHidden(true)
    }

    /// The one mark the goal makes on the row. An ending by hand takes the
    /// neutral vapour instead: the row already says it stopped, and a goal
    /// accent there would colour it like practice that ran its course.
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

    private var stampLine: String {
        let ending = record.completed ? "" : "stopped "
        return "\(record.startedAt.formatted(Self.clock)) · \(ending)"
            + record.duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    /// Speak both duration units so partial minutes are not lost.
    private var spokenLabel: String {
        let ending = record.completed ? "" : "stopped after "
        let length = record.duration
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))

        return "\(name), \(cycles)\(record.startedAt.formatted(Self.clock)), \(ending)\(length)"
    }

    /// Spoken but never printed: a fourth number on the line stops the log
    /// being scannable. The count is the cycles wholly finished, not the
    /// cycles planned. Zero is dropped, because the length already says that
    /// much. It carries its own separator, as `ending` above does.
    private var cycles: String {
        guard let figure = SessionSummaryLines.counted(record.cyclesCompleted, of: "cycle") else {
            return ""
        }
        return "\(figure.value) \(figure.label), "
    }
}
