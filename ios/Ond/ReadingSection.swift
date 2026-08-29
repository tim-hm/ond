import OndKit
import OndUI
import SwiftUI

/// A named group of long-form topics, shared by screens that teach rather
/// than present a list of actions. The section owns the complete reading
/// hierarchy — title, topic headings, body copy, scaled spacing — so its
/// consumers cannot drift apart. `LabelledSection` stays the shallower
/// pattern for shelves and rows.
struct ReadingSection: View {
    /// One heading and its answer inside a reading section.
    struct Topic: Identifiable {
        let id: String
        let title: String
        let content: ReadingContent
        /// A one-word mark beside the heading. Only the evidence topic has
        /// one: a reader arriving at the detail deserves the verdict before
        /// the copy rather than after.
        var grade: EvidenceGrade?
    }

    let title: String
    let topics: [Topic]

    @ScaledMetric(relativeTo: .body) private var headingToBodySpacing = 4
    @ScaledMetric(relativeTo: .body) private var sectionToContentSpacing = 8
    @ScaledMetric(relativeTo: .body) private var topicSpacing = 16
    @ScaledMetric(relativeTo: .body) private var listSpacing = 8
    @ScaledMetric(relativeTo: .body) private var leadToListSpacing = 12
    @ScaledMetric(relativeTo: .body) private var markerWidth = 22
    @ScaledMetric(relativeTo: .body) private var bulletSize = 5
    @ScaledMetric(relativeTo: .body) private var bulletTopInset = 8

    var body: some View {
        VStack(alignment: .leading, spacing: sectionToContentSpacing) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Ink.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: topicSpacing) {
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: headingToBodySpacing) {
                        HStack(spacing: Theme.Spacing.close) {
                            Text(topic.title)
                                .font(.headline)
                                .foregroundStyle(Theme.Ink.primary)
                                .accessibilityAddTraits(.isHeader)

                            if let grade = topic.grade {
                                EvidenceChip(grade: grade, color: Theme.Ink.primary)
                            }
                        }

                        reading(topic.content, topicID: topic.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A lead paragraph and its list are two blocks, so the gap between them is
    /// a paragraph's rather than the topic's tighter heading-to-body gap.
    private func reading(_ content: ReadingContent, topicID: String) -> some View {
        VStack(alignment: .leading, spacing: leadToListSpacing) {
            if !content.lead.isEmpty {
                Text(content.lead)
                    .font(.body)
                    .foregroundStyle(Theme.Ink.secondary)
                    .accessibilityIdentifier("reading-\(topicID)-lead")
            }

            if !content.items.isEmpty {
                VStack(alignment: .leading, spacing: listSpacing) {
                    ForEach(Array(content.items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: Theme.Spacing.close) {
                            marker(for: content.listStyle, index: index)

                            Text(item)
                                .font(.body)
                                .foregroundStyle(Theme.Ink.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(
                            for: content.listStyle,
                            index: index,
                            item: item
                        ))
                        .accessibilityIdentifier("reading-\(topicID)-item-\(index + 1)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for style: ReadingListStyle, index: Int) -> some View {
        switch style {
        case .none:
            Color.clear
                .frame(width: markerWidth, height: 0)
        case .bullets:
            Circle()
                .fill(Theme.Ink.primary)
                .frame(width: bulletSize, height: bulletSize)
                .padding(.top, bulletTopInset)
                .frame(width: markerWidth, alignment: .trailing)
        case .numbered:
            Text("\(index + 1).")
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.Ink.primary)
                .frame(width: markerWidth, alignment: .trailing)
        }
    }

    private func accessibilityLabel(
        for style: ReadingListStyle,
        index: Int,
        item: String
    ) -> String {
        switch style {
        case .none, .bullets: item
        case .numbered: "Step \(index + 1). \(item)"
        }
    }
}
