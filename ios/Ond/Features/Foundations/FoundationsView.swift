import OndKit
import OndUI
import SwiftUI

/// The questions most breathing apps never answer: belly or chest, nose or
/// mouth, what a hold is for, how long a sitting is worth, and whether any of
/// it lasts.
///
/// Reference data rather than copy, so the same answers can reach the session
/// screen and, later, the assistant. The framing is the point — every one of
/// these is a suggestion, and the footer says so out loud.
struct FoundationsView: View {
    @State private var model: FoundationsModel

    init(model: FoundationsModel) {
        _model = State(wrappedValue: model)
    }

    var body: some View {
        content
            .paletteGround()
            .navigationTitle("The basics")
            // Stated, not inherited: the Coach root it is pushed from is
            // inline, and `.automatic` would quietly follow it.
            .navigationBarTitleDisplayMode(.large)
            .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()

        case let .loaded(topics):
            List {
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                        Text(topic.question)
                            .font(.headline)
                        FoundationIllustration(slug: topic.slug)
                        Text(topic.answer)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.standard)
                    .accessibilityElement(children: .combine)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Text("All of this is a suggestion, never a rule. The breathing works while "
                    + "you're still learning it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)

        case let .failed(message):
            ContentUnavailableView {
                Label("Can't reach the basics", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    Task { await model.load() }
                }
            }
        }
    }
}
