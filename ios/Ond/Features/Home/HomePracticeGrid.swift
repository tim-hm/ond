import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Home's immediate practice context in four cards.
///
/// Rhythm and recency are readings; Suggested and Repeat are actions. Keeping
/// those four answers in one grid makes their relationship visible without
/// turning the first half of Home into a stack of sections. At accessibility
/// text sizes the grid becomes a column so the two-column rhythm never costs
/// legibility.
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
            systemImage: "calendar",
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
            systemImage: "clock",
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
                systemImage: "sparkles",
                stop: suggested,
                tier: tier,
                identifier: "suggested-card"
            ) {
                start(suggested)
            }
        } else {
            PracticeUnavailableCard(
                caption: "Suggested now",
                systemImage: "sparkles",
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
                systemImage: "arrow.clockwise",
                stop: repeatLast,
                tier: tier,
                identifier: "repeat-card"
            ) {
                start(repeatLast)
            }
        } else {
            PracticeUnavailableCard(
                caption: "Repeat last",
                systemImage: "arrow.clockwise",
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
    let systemImage: String
    let headline: String
    let detail: String
    let accessibilityLabel: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            PracticeCardHeading(
                caption: caption,
                systemImage: systemImage,
                accent: Theme.Accent.brand
            )

            Text(headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Ink.primary)

            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Ink.secondary)
        }
        .practiceCardContent()
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}

private struct PracticeActionCard: View {
    let caption: String
    let systemImage: String
    let stop: DialStop
    let tier: SubscriptionTier
    let identifier: String
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                PracticeCardHeading(
                    caption: caption,
                    systemImage: systemImage,
                    accent: stop.goal.accent
                )

                Text(stop.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Ink.primary)

                HStack(spacing: Theme.Spacing.close) {
                    // The goal's one mark on the card, at full strength — the
                    // tint fill this replaced was too weak to tell two
                    // neighbouring goals apart, and coloured nothing legibly.
                    Circle()
                        .fill(stop.goal.accent)
                        .frame(width: 6, height: 6)

                    Text(stop.facts(for: tier))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }
            .practiceCardContent()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(caption), \(stop.spokenLabel(for: tier))")
        .accessibilityHint("Starts the session")
        .accessibilityIdentifier(identifier)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Interactive because the card is itself the button — the press gets
        // the material's flex rather than no answer at all.
        .glassCard(interactive: true)
    }
}

private struct PracticeUnavailableCard: View {
    let caption: String
    let systemImage: String
    let detail: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.close) {
            PracticeCardHeading(
                caption: caption,
                systemImage: systemImage,
                accent: Theme.Ink.tertiary
            )

            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Ink.secondary)
        }
        .practiceCardContent()
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct PracticeCardHeading: View {
    let caption: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.close) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: Theme.Spacing.loose, height: Theme.Spacing.loose)
                .accessibilityHidden(true)

            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Ink.secondary)
        }
    }
}

private extension View {
    func practiceCardContent() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Theme.Spacing.standard)
            .padding(.vertical, Theme.Spacing.loose)
    }
}
