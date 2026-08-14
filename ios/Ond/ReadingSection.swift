import OndUI
import SwiftUI

/// A named group of long-form topics, shared by screens that teach rather than
/// present a list of actions.
///
/// The section owns the complete reading hierarchy so its consumers cannot
/// drift independently: a section title, topic headings, body copy and the
/// scaled space between all three. `LabelledSection` remains the shallower
/// pattern for shelves and rows.
struct ReadingSection: View {
    /// One heading and its answer inside a reading section.
    struct Topic: Identifiable {
        let id: String
        let title: String
        let body: String
    }

    let title: String
    let topics: [Topic]

    @ScaledMetric(relativeTo: .body) private var headingToBodySpacing = 4
    @ScaledMetric(relativeTo: .body) private var sectionToContentSpacing = 8
    @ScaledMetric(relativeTo: .body) private var topicSpacing = 16

    var body: some View {
        VStack(alignment: .leading, spacing: sectionToContentSpacing) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Ink.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: topicSpacing) {
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: headingToBodySpacing) {
                        Text(topic.title)
                            .font(.headline)
                            .foregroundStyle(Theme.Ink.primary)
                            .accessibilityAddTraits(.isHeader)

                        Text(topic.body)
                            .font(.body)
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
