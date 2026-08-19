import OndKit
import OndStyle
import OndUI
import SwiftUI

/// Everything the app asks about the person, on one screen: what to call them,
/// what brought them here, and how much they want explained.
///
/// Three questions where there used to be three screens, and none of them is
/// required — the name is a greeting, the goals decide what is shown first, and
/// the experience level only chooses how much a session narrates. Skip takes
/// all three unanswered, and every one of them is editable in Settings
/// afterwards.
struct YouStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(
            title: "A little about you",
            subtitle: "None of this is required."
        ) {
            name
            goals
            experience
        }
    }

    /// The one field in the flow somebody types into.
    ///
    /// The placeholder is the whole label, which works because the question is
    /// four words and the answer is a word: a heading above an empty field
    /// would be the same sentence twice. VoiceOver reads the placeholder as the
    /// field's label, so it is not lost with the hint.
    private var name: some View {
        TextField("What should we call you?", text: $model.givenName)
            .font(.body)
            .foregroundStyle(Theme.Ink.primary)
            // A given name, so iOS offers the one on the device rather than
            // treating this as a new credential to save.
            .textContentType(.givenName)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(Theme.Spacing.standard)
            .glassCard()
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
            heading("What brings you here?", detail: "Pick as many as you like.")

            OnboardingGoalLayout(spacing: Theme.Spacing.close) {
                ForEach(TechniqueGoal.allCases, id: \.self) { goal in
                    OnboardingChoice(
                        title: goal.title,
                        isSelected: model.isSelected(goal),
                        accent: goal.accent,
                        selectedText: goal == .calm ? Theme.Accent.brandText : goal.textAccent
                    ) {
                        model.toggle(goal)
                    }
                }
            }
        }
    }

    /// One row rather than the three full-width cards this used to be.
    ///
    /// It is the least consequential answer on the screen — every exercise is
    /// available at every level, and all it decides is how much a session
    /// explains — so it takes the least room, and nothing underneath narrates
    /// what the choice will do. The row states the question and the answer,
    /// which between them are the whole control.
    private var experience: some View {
        OnboardingPickerRow("Done this before?", selection: $model.experienceLevel) {
            OptionalPickerOptions<ExperienceLevel>()
        }
    }

    /// A question inside the step, under the step's own heading — smaller than
    /// the title above it, so the screen reads as one page with parts rather
    /// than as three headings competing.
    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Ink.primary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, Theme.Spacing.close)
    }
}

/// A leading-aligned flow that wraps chips only when the next whole word would
/// exceed the available width.
private struct OnboardingGoalLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(for: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height }
            + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row]()
        var row = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = row.width == 0 ? size.width : row.width + spacing + size.width
            if nextWidth > width, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.append(subview, size: size, spacing: spacing)
        }

        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }

    private struct Item {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items = [Item]()
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(_ subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            width += (items.isEmpty ? 0 : spacing) + size.width
            height = max(height, size.height)
            items.append(Item(subview: subview, size: size))
        }
    }
}
