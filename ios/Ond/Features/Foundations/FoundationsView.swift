import OndKit
import OndUI
import SwiftUI

struct FoundationsView: View {
    private static let leadSlug = "what-matters-most"
    private static let breathSlugs = [
        "what-a-good-breath-feels-like",
        "is-a-deep-breath-the-answer",
        "why-it-works",
        "belly-or-chest",
        "nose-or-mouth",
        "how-slow",
    ]
    private static let safetySlugs = [
        "fast-breathing-and-holds",
        "getting-comfortable",
        "when-breathing-is-the-problem",
    ]
    private static let practiceSlugs = [
        "how-long",
        "how-good-is-the-evidence",
        "why-no-scores",
    ]

    @ScaledMetric(relativeTo: .body) private var sectionSpacing = 24

    @State private var model: FoundationsModel

    init(model: FoundationsModel) {
        _model = State(wrappedValue: model)
    }

    var body: some View {
        content
            .paletteGround()
            .navigationTitle("The basics")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ReferenceLoadingView(.titled)

        case let .loaded(topics):
            foundations(topics)

        case .failed:
            ReferenceRetryView(
                title: "The basics aren’t available yet",
                message: "We couldn’t load the Basics. Try again."
            ) {
                Task { await model.refresh() }
            }
        }
    }

    private func foundations(_ topics: [FoundationTopic]) -> some View {
        let lead = topics.first { $0.slug == Self.leadSlug }
        let breath = selectedTopics(in: Self.breathSlugs, from: topics)
        let safety = selectedTopics(in: Self.safetySlugs, from: topics)
        let known = Set(
            [Self.leadSlug] + Self.breathSlugs + Self.safetySlugs + Self.practiceSlugs
        )
        let practice = topics.filter {
            Self.practiceSlugs.contains($0.slug) || !known.contains($0.slug)
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                if let lead {
                    foundationSection("Overview", topics: [lead])
                }

                foundationSection("The breath", topics: breath)
                foundationSection("Safety and comfort", topics: safety)
                foundationSection("Practice and evidence", topics: practice)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical)
        }
    }

    private func selectedTopics(
        in slugs: [String],
        from topics: [FoundationTopic]
    ) -> [FoundationTopic] {
        topics.filter { slugs.contains($0.slug) }
    }

    @ViewBuilder
    private func foundationSection(_ title: String, topics: [FoundationTopic]) -> some View {
        if !topics.isEmpty {
            ReadingSection(
                title: title,
                topics: topics.map {
                    ReadingSection.Topic(
                        id: $0.slug,
                        title: $0.question,
                        content: $0.answerContent
                    )
                }
            )
        }
    }
}
