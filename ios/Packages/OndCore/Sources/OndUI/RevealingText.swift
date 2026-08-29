import SwiftUI

/// A paragraph as it is being written: the newest words arrive behind a soft
/// edge. The whole paragraph stays one `Text` — a `TextRenderer` is handed a
/// finished `Text.Layout`, so line breaking, Dynamic Type and the VoiceOver
/// string cost the reveal nothing. `isStreaming: false` settles the tail, and a
/// resumed paragraph never fades; `pace` is one publish's window, matching the reveal to it.
public struct RevealingText: View {
    private let text: String
    private let isStreaming: Bool
    private let pace: Duration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the reveal has travelled, in glyphs, as a continuous value the
    /// animation interpolates between two publishes.
    @State private var revealed: Double = 0

    public init(_ text: String, isStreaming: Bool, pace: Duration) {
        self.text = text
        self.isStreaming = isStreaming
        self.pace = pace
    }

    public var body: some View {
        Text(text)
            // Applied unconditionally and settled by pushing `revealed` past the
            // end, rather than dropped once the reply finishes: dropping it
            // changes the view's identity, and the finished paragraph flashes as
            // SwiftUI swaps one view for another. Past the end every run takes
            // the whole-run path, so a settled paragraph costs a plain `Text`.
            .textRenderer(WipeRenderer(revealed: revealed))
            .onAppear {
                // A paragraph that was already finished when it appeared is
                // opaque from its first frame. Fading in a transcript somebody
                // read last week would be the screen pretending to write it.
                if isStreaming, !reduceMotion {
                    step(to: text)
                } else {
                    revealed = settled(text)
                }
            }
            .onChange(of: text) { _, arrived in step(to: arrived) }
            .onChange(of: isStreaming) { _, _ in step(to: text) }
    }

    /// Where `revealed` has to reach for every glyph to be fully opaque — one
    /// window past the end, because the ramp is measured backwards from it.
    private func settled(_ text: String) -> Double {
        Double(text.count) + WipeRenderer.window
    }

    private func step(to arrived: String) {
        // Reduce Motion suppresses the ramp, not the pacing. Text arriving in
        // steps is content; a soft edge travelling across a paragraph is the
        // directional motion the setting is about.
        guard !reduceMotion else {
            revealed = settled(arrived)
            return
        }

        // While more is coming the frontier stops at the end of what arrived, so
        // the last couple of words sit part-drawn — the soft edge. Settling
        // carries it past the end and fills them in.
        let target = isStreaming ? Double(arrived.count) : settled(arrived)
        withAnimation(.linear(duration: pace.seconds)) {
            revealed = target
        }
    }
}

/// Paints a `Text` up to `revealed`, behind an edge that ramps rather than cuts.
struct WipeRenderer: TextRenderer {
    var revealed: Double

    /// How wide the soft edge is, in glyphs — about two words. Narrower reads as
    /// a cursor chasing the text; wider as a paragraph somebody smeared.
    static let window: Double = 12

    var animatableData: Double {
        get { revealed }
        set { revealed = newValue }
    }

    /// Cost is bounded by the window rather than by the length of the reply:
    /// runs behind the edge are one draw call each, runs ahead of it are none at
    /// all, and only the dozen glyphs inside pay per glyph.
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        for line in layout {
            for run in line {
                let start = index
                index += run.count

                if Double(index) <= revealed - Self.window {
                    context.draw(run)
                    continue
                }
                if Double(start) >= revealed {
                    continue
                }

                // One copy for the whole run, reassigned per glyph: `opacity` is
                // an absolute multiplier rather than something that compounds,
                // so copying the context again per glyph would buy nothing.
                var ink = context
                for (offset, glyph) in run.enumerated() {
                    ink.opacity = Self.opacity(ofGlyph: start + offset, at: revealed)
                    ink.draw(glyph)
                }
            }
        }
    }

    /// The ramp itself, out here so a test can pin its ends without a display.
    ///
    /// Measured backwards from the frontier: a glyph the reveal has just reached
    /// is invisible, and it is fully drawn once the frontier is a window past it.
    static func opacity(ofGlyph index: Int, at revealed: Double) -> Double {
        min(1, max(0, (revealed - Double(index)) / window))
    }
}

private extension Duration {
    /// This type's own unit for the animation APIs, which speak in seconds.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
