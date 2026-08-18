import OndKit
import OndStyle
import OndUI
import SwiftUI

/// One past session: what it was, when, and how long it ran.
///
/// The goal's dot leads, as it does on every row in the app — and a session
/// whose exercise has since gone from the catalogue takes the neutral vapour
/// instead of a guess, because a colour is a claim about what the session was
/// for and this device no longer knows.
///
/// **An early ending is stated plainly and nothing more is made of it.** The
/// row says the length that was actually breathed and then says it ended early,
/// in that order: what happened, then the qualification. The refresh spec asks
/// for the plan it fell short of — "ended at 1:12 of 5:00" — and no record holds
/// one: `SessionRecord` carries what was breathed, never what was intended, so
/// the comparison would be a number this row invented.
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
        .padding(.vertical, Theme.Spacing.tight)
        // `.ignore` with a label of its own rather than `.combine`, which takes
        // the union of its children's frames: across a row whose halves are
        // pushed apart by a `Spacer`, that is a node the width of the screen
        // spanning three different foregrounds and a stretch of bare ground.
        // The accessibility audit measures contrast over exactly that node, and
        // reported a failure no single pairing here can account for — every one
        // of them clears AA measured on its own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// How a session's moment is written, spoken and seen alike — one constant
    /// so the sentence VoiceOver reads cannot drift from the words beside it.
    private static let stamp = Date.FormatStyle(date: .abbreviated, time: .shortened)

    /// The row as one sentence, in the order the eye reads it.
    private var spokenLabel: String {
        "\(name), \(detail), \(record.startedAt.formatted(Self.stamp))"
    }

    /// The goal's one mark on the row. The words beside it never depend on it,
    /// so the colour is reinforcement rather than the carrier.
    private var dot: some View {
        Circle()
            .fill(goal?.accent ?? Theme.Breath.exhale.opacity(0.35))
            .frame(width: 6, height: 6)
            // Nudged down off the text baseline it is aligned to, so it sits
            // against the middle of the name rather than under it.
            .alignmentGuide(.firstTextBaseline) { $0.height }
            .accessibilityHidden(true)
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
                .font(.body)
                .foregroundStyle(Theme.Ink.primary)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
    }

    private var timestamp: some View {
        Text(record.startedAt, format: Self.stamp)
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
