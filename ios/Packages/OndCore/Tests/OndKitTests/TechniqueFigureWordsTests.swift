import CoreGraphics
import Foundation
import OndKit
import Testing

/// What a figure says about itself — the words on it, and the sentence a
/// screen reader hears in place of it.
///
/// A suite of its own rather than a section of `TechniqueFigureTests`: the
/// geometry there is about shape, and this is about language. They share only
/// the fixtures, which is what `SeededCatalogue` is for.
@Suite("What a figure says")
struct TechniqueFigureWordsTests {
    /// The silhouette a technique draws, rounded to a thousandth so a
    /// floating-point wobble is never mistaken for a different picture.
    private func silhouette(of technique: Technique) -> String {
        TechniqueFigure.all(for: technique)
            .flatMap(SeededCatalogue.points(of:))
            .map { "\(($0.x * 1000).rounded()),\(($0.y * 1000).rounded())" }
            .joined(separator: " ")
    }

    /// A technique's cycle reduced to what the drawing can state: each stage's
    /// phase kinds and their shares of the cycle. Two techniques with the same
    /// signature *should* draw the same picture — box and long box, coherent
    /// and bellows — because a cycle cannot say 5½ seconds against 1; their
    /// labels carry the tempo.
    private func signature(of technique: Technique) -> String {
        technique.stages.map { stage in
            let total = max(stage.phases.reduce(0.0) { $0 + $1.duration.seconds }, 0.001)
            return stage.phases
                .map { "\($0.kind):\((($0.duration.seconds / total) * 1000).rounded())" }
                .joined(separator: " ")
        }
        .joined(separator: " | ")
    }

    /// The collisions a one-cycle figure allows are the honest kind: the same
    /// ratios draw the same shape. Derived from the phases rather than kept as
    /// a slug list, so a reseeded duration moves both sides of the claim at
    /// once — a collision between different ratios means the construction has
    /// stopped stating a difference the phases do state.
    @Test("Only techniques that share their ratios share a silhouette")
    func silhouettesAreDistinct() {
        var seen: [String: Technique] = [:]

        for technique in SeededCatalogue.techniques {
            let drawn = silhouette(of: technique)
            if let other = seen[drawn] {
                #expect(
                    signature(of: technique) == signature(of: other),
                    "`\(technique.slug)` draws the same as `\(other.slug)` with different ratios"
                )
            }
            seen[drawn] = technique
        }
    }

    /// The claim that matters on screen: whatever the silhouettes do, no two
    /// techniques are the same drawing once their labels are on them.
    @Test("Every seeded technique draws something no other technique draws")
    func everyTechniqueIsDistinct() {
        var seen: [String: String] = [:]

        for technique in SeededCatalogue.techniques {
            let labels = TechniqueFigure.all(for: technique)
                .flatMap(\.labels)
                .map(\.text)
                .joined(separator: " ")
            let drawn = "\(silhouette(of: technique)) \(labels)"

            #expect(
                seen[drawn] == nil,
                "`\(technique.slug)` draws the same as `\(seen[drawn] ?? "")`"
            )
            seen[drawn] = technique.slug
        }
    }

    /// Every figure has to fit the box it is handed, whatever the durations.
    @Test("Every seeded technique stays inside its frame")
    func everyFigureFitsItsFrame() {
        for technique in SeededCatalogue.techniques {
            for drawn in TechniqueFigure.all(for: technique) {
                for point in SeededCatalogue.points(of: drawn) {
                    #expect(point.x >= -0.001 && point.x <= 1.001, "`\(technique.slug)`")
                    #expect(point.y >= -0.001 && point.y <= 1.001, "`\(technique.slug)`")
                }
            }
        }
    }

    /// A label hangs off a point on the drawing and is pushed clear of it from
    /// there, so an anchor outside the figure is a word floating in space —
    /// which is what the open-ended retention did the moment staged techniques
    /// started labelling themselves: its `hold` was hung at full lungs, a
    /// figure's height above a drawing that never leaves empty ones.
    @Test("Every label hangs off a point inside the figure it names")
    func labelsAnchorInsideTheirFigure() {
        for technique in SeededCatalogue.techniques {
            for figure in TechniqueFigure.all(for: technique) {
                let bounds = figure.bounds.insetBy(dx: -0.001, dy: -0.001)

                for label in figure.labels {
                    #expect(bounds.contains(label.at), "`\(technique.slug)` — \(label.text)")
                }
            }
        }
    }

    /// The chart is hidden from VoiceOver and the row of phase capsules that
    /// used to carry these facts as text is gone, so this string is now the only
    /// thing a screen reader has. It is also the generated SVG's `aria-label`,
    /// which is what makes the page and the app describe a technique alike.
    @Test("The description names every phase, in order, with its length")
    func describesEveryPhase() {
        let description = SeededCatalogue.figure("box-breathing").description

        #expect(description == """
        One cycle: Breathe in for 4 seconds, Hold for 4 seconds, \
        Breathe out for 4 seconds, Hold for 4 seconds. Repeated 19 times.
        """)
    }

    /// The figure draws one cycle whatever the exercise repeats, so the repeat
    /// count lives in the sentence and nowhere else — and a stage breathed once
    /// must not claim a repetition it does not have.
    @Test("The description carries the repeat count the drawing does not")
    func describesTheRepeats() {
        #expect(SeededCatalogue.figure("coherent-breathing").description
            .hasSuffix("Repeated 27 times."))
        #expect(SeededCatalogue.figure("physiological-sigh").description
            .hasSuffix("Repeated 3 times."))
    }

    /// Bellows breath is the one exercise whose phases last exactly a second,
    /// so it is the one that says "1 seconds" if the length is glued to a bare
    /// plural. Somebody using a screen reader hears every one of these.
    @Test("A one-second phase is spoken in the singular")
    func describesASingleSecond() {
        let description = SeededCatalogue.figure("bellows-breath").description

        #expect(description.contains("for 1 second,"))
        #expect(!description.contains("1 seconds"))
    }

    /// A nostril hint is a fact the phase kind cannot carry, and somebody
    /// listening rather than looking needs it most.
    @Test("The description carries the nostril where there is one")
    func describesNostrils() {
        let description = SeededCatalogue.figure("alternate-nostril").description

        #expect(description.contains("Breathe in through your left nostril"))
        #expect(description.contains("Breathe out through your right nostril"))
    }

    /// An open-ended hold has no scheduled length to state — stating the
    /// dialled one would promise what the session does not keep — but its band
    /// is an example worth saying, the same one the label prints.
    @Test("The retention is described as the person's to end, with its band")
    func describesTheRetention() {
        let description = SeededCatalogue
            .figure("wim-hof-rounds", stage: SeededCatalogue.retention)
            .description

        #expect(description.contains("as long as you can"))
        #expect(description.contains("typically 30 seconds to 2 minutes"))
        #expect(!description.contains("60 seconds"))
    }
}
