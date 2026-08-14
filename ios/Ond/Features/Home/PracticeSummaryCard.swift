import OndKit
import OndUI
import SwiftUI

/// A compact reading of the practice that opens its complete session history.
///
/// One raised content surface rather than a streak card followed by three
/// statistic tiles: the four values describe one practice, and separating each
/// into a card made the fold look like four equal destinations. This is not
/// glass because it belongs to the content layer. The chevron and the system
/// link semantics carry its second job as the way into Sessions.
struct PracticeSummaryCard<Destination: View>: View {
    let stats: JourneyStats
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                HStack(alignment: .center, spacing: Theme.Spacing.close) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        if let stage = stats.stage {
                            Text(stage.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.Ink.secondary)
                        }

                        Text(stats.streakHeadline)
                            .font(.headline)
                            .foregroundStyle(Theme.Ink.primary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.Ink.tertiary)
                        .accessibilityHidden(true)
                }

                Text(stats.streakDetail)
                    .font(.callout)
                    .foregroundStyle(Theme.Ink.secondary)

                Divider()
                    .overlay(Theme.Surface.line)

                metrics
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.standard)
            .background(
                Theme.Surface.raised,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows sessions and practice history")
    }

    /// Three inline readings at ordinary sizes and the same readings stacked
    /// when their uncompressed words no longer fit side by side.
    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.close) {
                metric(stats.daysPractised, singular: "day", plural: "days")
                Spacer(minLength: 0)
                metricDivider
                Spacer(minLength: 0)
                metric(stats.sessions, singular: "session", plural: "sessions")
                Spacer(minLength: 0)
                metricDivider
                Spacer(minLength: 0)
                metric(stats.minutes, singular: "minute", plural: "minutes")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                metric(stats.daysPractised, singular: "day", plural: "days")
                metric(stats.sessions, singular: "session", plural: "sessions")
                metric(stats.minutes, singular: "minute", plural: "minutes")
            }
        }
    }

    private var metricDivider: some View {
        Divider()
            .overlay(Theme.Surface.line)
            .frame(height: 24)
    }

    private func metric(_ value: Int, singular: String, plural: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.tight) {
            Text(value, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.Ink.primary)
            Text(unit(for: value, singular: singular, plural: plural))
                .font(.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var accessibilityLabel: String {
        let summary = [stats.stage?.title, stats.streakHeadline, stats.streakDetail]
            .compactMap(\.self)
            .joined(separator: ", ")
        let totals = [
            count(stats.daysPractised, singular: "day", plural: "days"),
            count(stats.sessions, singular: "session", plural: "sessions"),
            count(stats.minutes, singular: "minute", plural: "minutes"),
        ].joined(separator: ", ")
        return "\(summary), \(totals)"
    }

    private func count(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(unit(for: value, singular: singular, plural: plural))"
    }

    private func unit(for value: Int, singular: String, plural: String) -> String {
        value == 1 ? singular : plural
    }
}
