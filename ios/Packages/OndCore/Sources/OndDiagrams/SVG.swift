import CoreGraphics
import Foundation
import OndKit

/// One technique's small figure as inline SVG, in the site's own idiom, plus
/// the element and formatting helpers the wide plot shares.
enum SVG {
    static let vocabulary = Markers.Vocabulary(kind: "figure")

    /// The site's viewBox, kept from the figures this replaces so the
    /// surrounding CSS and the column width it was tuned against still hold.
    static let box = CGSize(width: 220, height: 170)
    /// Room for the labels, which sit outside the drawing.
    ///
    /// Labels are vertical-only by `TechniqueFigure.Label`'s contract, so the
    /// height holds a line of text and the width only the overhang of a label
    /// centred near the figure's edge — half of `out · 6 L` at 11px.
    static let margin = CGSize(width: 28, height: 24)
    /// How far a label sits from the point it names.
    static let labelOffset = 14.0
    /// The site strokes its figures at 1.5 and its baselines at 1.
    static let lineWidth = 1.5

    /// The indentation the drawings sit at in the hand-written page. Matched
    /// rather than inferred: the generator owns only the span between the
    /// markers, and output that did not line up with the HTML either side of it
    /// would make every regeneration look like a reformat.
    static let indent = String(repeating: " ", count: 12)

    /// The gap between a staged technique's stages.
    static let gap = 10.0

    static func figure(for technique: Technique) -> String {
        let figures = TechniqueFigure.all(for: technique)
        var body: [String] = []

        // A staged technique draws its figures side by side in one viewBox, the
        // same arrangement the phone's chart uses.
        for (index, figure) in figures.enumerated() {
            let cell = cell(index: index, of: figures.count, in: content(of: box, inside: margin))
            let transform = figure.transform(into: cell, lineWidth: lineWidth)

            body += figure.drawable.map { path($0, through: transform, at: lineWidth) }
            body += figure.labels.map { text($0, through: transform) }
        }

        return document(box: box, label: figures.spoken, body: body)
    }

    // MARK: Layout

    /// One drawing's `<svg>` element, around body lines a renderer has already
    /// produced.
    ///
    /// Shared with the plot rather than written twice, because what is in here
    /// is a contract with the hand-written page either side of it: the trailing
    /// indent is what lands the closing marker in the same column as the
    /// opening one, and a regeneration that got it wrong would read as a
    /// reformat of the whole file.
    static func document(box: CGSize, label: String, body: [String]) -> String {
        let inner = indent + "  "
        var lines = [
            "\(indent)<svg",
            "\(inner)viewBox=\"0 0 \(number(box.width)) \(number(box.height))\"",
            "\(inner)width=\"\(number(box.width))\"",
            "\(inner)height=\"\(number(box.height))\"",
            "\(inner)aria-label=\"\(escape(label))\"",
            "\(indent)>",
        ]
        lines += body.map { inner + $0 }
        lines.append("\(indent)</svg>")

        return "\n" + lines.joined(separator: "\n") + "\n" + indent
    }

    /// The drawable rect inside a box's label margin.
    static func content(of box: CGSize, inside margin: CGSize) -> CGRect {
        CGRect(
            x: margin.width,
            y: margin.height,
            width: box.width - margin.width * 2,
            height: box.height - margin.height * 2
        )
    }

    /// How wide one stage's cell is, across the room the stages share.
    ///
    /// Its own function because the plot needs the width *before* it has a box
    /// to lay cells into — the height it is deriving depends on it. Two
    /// spellings of this arithmetic would let the plot's height and its cells
    /// disagree, and a figure fitted into a cell it does not match letterboxes
    /// silently: `check:diagrams` pins the generated SVG, so both sides would
    /// simply regenerate to the same wrong answer.
    static func cellWidth(of count: Int, across width: Double, gap: Double) -> Double {
        let count = Double(max(count, 1))
        return (width - gap * (count - 1)) / count
    }

    /// The rect one stage's drawing is placed into, side by side with the rest.
    ///
    /// Shared for the reason `TechniqueFigure.transform` is shared, and it is
    /// the same rule one step out: this decides the rect the fit is handed, so
    /// a second copy moves a drawing without either renderer noticing.
    static func cell(index: Int, of count: Int, in content: CGRect, gap: Double = gap) -> CGRect {
        guard count > 1 else { return content }

        let width = cellWidth(of: count, across: content.width, gap: gap)
        return CGRect(
            x: content.minX + (width + gap) * Double(index),
            y: content.minY,
            width: width,
            height: content.height
        )
    }

    // MARK: Elements

    /// - Parameter width: the weight the drawing is stroked at, which the
    ///   figure and the plot answer differently — and which a hold is drawn
    ///   twice at, so the plot can overdraw its plateaus.
    static func path(
        _ stroke: TechniqueFigure.Stroke,
        through transform: CGAffineTransform,
        at width: CGFloat
    ) -> String {
        var d: [String] = []
        for command in stroke.commands {
            switch command {
            case let .move(point):
                d.append("M\(pair(point, transform))")
            case let .line(point):
                d.append("L\(pair(point, transform))")
            case let .curve(point, control1, control2):
                d.append(
                    "C\(pair(control1, transform)) \(pair(control2, transform)) \(pair(point, transform))"
                )
            }
        }

        let dash = stroke.dashed
            ? " stroke-dasharray=\"\(TechniqueFigure.Stroke.dash.map { number($0) }.joined(separator: " "))\""
            : ""

        return """
        <path d="\(d.joined(separator: " "))" fill="none" \
        stroke-width="\(number(stroke.weight(on: width)))" stroke-linecap="round" \
        stroke-linejoin="round"\(dash) \
        class="\(className(stroke.ink))" />
        """
    }

    static func text(
        _ label: TechniqueFigure.Label,
        through transform: CGAffineTransform
    ) -> String {
        let offset = labelOffset
        let anchor = label.at.applying(transform)
        // Pushed clear of the run it names along the perpendicular — (-sin,
        // cos) is the run's normal on the below side, y downwards — then tilted
        // to the run's own slope. The transform is uniform, so the angle
        // survives it.
        let side = label.below ? 1.0 : -1.0
        let placed = CGPoint(
            x: anchor.x + side * -sin(label.angle) * offset,
            y: anchor.y + side * cos(label.angle) * offset
        )

        let tilt = label.angle == 0
            ? ""
            : " transform=\"rotate(\(number(label.angle * 180 / .pi)) "
            + "\(number(placed.x)) \(number(placed.y)))\""

        return """
        <text x="\(number(placed.x))" y="\(number(placed.y))" \
        text-anchor="middle" dominant-baseline="middle"\(tilt)>\(escape(label.text))</text>
        """
    }

    /// The stroke classes `web/style.css` colours. Named for the moment of
    /// breath, like the ink they come from.
    static func className(_ ink: TechniqueFigure.Ink) -> String {
        switch ink {
        case .inhale: "stroke-in"
        case .exhale: "stroke-out"
        case .hold: "stroke-hold"
        case .baseline: "stroke-baseline"
        }
    }

    // MARK: Formatting

    static func pair(_ point: CGPoint, _ transform: CGAffineTransform) -> String {
        let placed = point.applying(transform)
        return "\(number(placed.x)) \(number(placed.y))"
    }

    /// At most two decimals, and no trailing zeros — the committed diff should
    /// be readable, and a coordinate is not meaningful past a hundredth of a
    /// point.
    static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%g", rounded)
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
