import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Home's immediate practice context in four compact cards.
///
/// Rhythm and recency are readings; Suggested and Repeat are actions. Keeping
/// those four answers in one grid makes their relationship visible without
/// turning the first half of Home into a stack of sections. At accessibility
/// text sizes the grid becomes a column so compactness never costs legibility.
struct HomePracticeGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let stats: JourneyStats
    let lastSessionAt: Date?
    let suggested: DialStop?
    let repeatLast: DialStop?
    let tier: SubscriptionTier
    let start: (DialStop) -> Void

    var body: some View {
        if let lastSessionAt {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                cards(lastSession: lastSessionAt.formatted(.relative(presentation: .named)))
            }
        } else {
            cards(lastSession: nil)
        }
    }

    @ViewBuilder
    private func cards(lastSession: String?) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.close) {
                rhythmCard
                lastSessionCard(relative: lastSession)
                suggestedCard
                repeatCard
            }
        } else {
            Grid(
                horizontalSpacing: Theme.Spacing.close,
                verticalSpacing: Theme.Spacing.close
            ) {
                GridRow {
                    rhythmCard
                    lastSessionCard(relative: lastSession)
                }

                GridRow {
                    suggestedCard
                    repeatCard
                }
            }
        }
    }

    private var rhythmCard: some View {
        PracticeStatusCard(
            caption: stats.stage?.title ?? "Practice rhythm",
            headline: stats.streakHeadline,
            detail: count(stats.daysPractised, singular: "day", plural: "days"),
            accessibilityLabel: [
                stats.stage?.title,
                stats.streakHeadline,
                stats.streakDetail,
                count(stats.daysPractised, singular: "day practised", plural: "days practised"),
            ]
            .compactMap(\.self)
            .joined(separator: ", "),
            identifier: "practice-rhythm-card"
        )
    }

    private func lastSessionCard(relative: String?) -> some View {
        PracticeStatusCard(
            caption: "Last session",
            headline: relative ?? "None yet",
            detail: [
                count(stats.sessions, singular: "session", plural: "sessions"),
                count(stats.minutes, singular: "minute", plural: "minutes"),
            ].joined(separator: " · "),
            accessibilityLabel: lastSessionAccessibilityLabel(relative: relative),
            identifier: "last-session-card"
        )
    }

    @ViewBuilder
    private var suggestedCard: some View {
        if let suggested {
            PracticeActionCard(
                caption: "Suggested now",
                stop: suggested,
                tier: tier,
                identifier: "suggested-card"
            ) {
                start(suggested)
            }
        } else {
            PracticeUnavailableCard(
                caption: "Suggested now",
                detail: "Finding the right practice",
                identifier: "suggested-card"
            )
        }
    }

    @ViewBuilder
    private var repeatCard: some View {
        if let repeatLast {
            PracticeActionCard(
                caption: "Repeat last",
                stop: repeatLast,
                tier: tier,
                identifier: "repeat-card"
            ) {
                start(repeatLast)
            }
        } else {
            PracticeUnavailableCard(
                caption: "Repeat last",
                detail: lastSessionAt == nil ? "After your first session" : "No longer available",
                identifier: "repeat-card"
            )
        }
    }

    private func lastSessionAccessibilityLabel(relative: String?) -> String {
        let time = relative.map { "Last session, \($0)" } ?? "No sessions yet"
        return [
            time,
            count(stats.sessions, singular: "session", plural: "sessions"),
            count(stats.minutes, singular: "minute", plural: "minutes"),
        ].joined(separator: ", ")
    }

    private func count(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

private struct PracticeStatusCard: View {
    let caption: String
    let headline: String
    let detail: String
    let accessibilityLabel: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Ink.secondary)

            Text(headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Ink.primary)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.standard)
        .background(
            Theme.Surface.raised,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}

private struct PracticeActionCard: View {
    let caption: String
    let stop: DialStop
    let tier: SubscriptionTier
    let identifier: String
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Ink.secondary)

                Text(stop.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Ink.primary)

                Text(stop.facts(for: tier))
                    .font(.caption)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.Spacing.standard)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(caption), \(stop.spokenLabel(for: tier))")
        .accessibilityHint("Starts the session")
        .accessibilityIdentifier(identifier)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            stop.goal.accent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
    }
}

private struct PracticeUnavailableCard: View {
    let caption: String
    let detail: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Ink.secondary)

            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.standard)
        .background(
            Theme.Surface.raised,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
