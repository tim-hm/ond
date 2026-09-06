import OndKit
import OndStyle
import OndUI
import SwiftUI

struct BreathRhythmChart: View {
    let technique: Technique

    var body: some View {
        let figures = TechniqueFigure.all(for: technique)
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                VStack(alignment: .leading, spacing: Theme.Spacing.close) {
                    Text(figures.count > 1 ? figure.stage.title(at: index) : "One cycle")
                        .font(.subheadline.weight(.semibold))
                    FigureStrokes(
                        figure: figure,
                        accent: Theme.Accent.brand,
                        lineWidth: 2.5,
                        dashed: true
                    )
                    .frame(height: figure.stage.openEnded ? 44 : 100)
                    .accessibilityHidden(true)

                    Text(TechniqueFigure.describeForDisplay(figure))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !figure.stage.openEnded {
                        Text("Seconds per phase · height shows the breathing pattern")
                            .font(.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figures.spoken)
    }
}

private extension TechniqueFigure {
    static func describeForDisplay(_ figure: TechniqueFigure) -> String {
        figure.labels.map(\.text).joined(separator: "  →  ")
    }
}
