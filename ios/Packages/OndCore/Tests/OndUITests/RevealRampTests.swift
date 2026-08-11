@testable import OndUI
import Testing

/// The one part of the reveal a test can reach at all: the wipe itself needs a
/// display and a laid-out `Text`, but the ramp it paints with is arithmetic.
@Suite("The reveal's soft edge")
struct RevealRampTests {
    private let window = WipeRenderer.window

    /// Both ends are clamped, so a glyph the frontier has long passed is
    /// fully drawn and one it has not reached is not drawn at all — the two
    /// cases the whole-run fast paths in `draw` depend on being exactly right.
    @Test("The ramp is clamped at both ends")
    func theRampIsClamped() {
        #expect(WipeRenderer.opacity(ofGlyph: 40, at: 4) == 0, "ahead of the frontier")
        #expect(WipeRenderer.opacity(ofGlyph: 0, at: 400) == 1, "long behind it")
        #expect(WipeRenderer.opacity(ofGlyph: 10, at: 10) == 0, "exactly at the frontier")
    }

    /// A glyph is fully drawn once the frontier is one window past it — which is
    /// why settling pushes `revealed` a window beyond the end of the text rather
    /// than to its last index.
    @Test("A glyph is opaque exactly one window behind the frontier")
    func aGlyphIsOpaqueOneWindowBack() {
        #expect(WipeRenderer.opacity(ofGlyph: 100, at: 100 + window) == 1)
        #expect(WipeRenderer.opacity(ofGlyph: 100, at: 100 + window - 0.5) < 1)
    }

    /// Monotonic in the frontier: a glyph only ever gets more drawn as the reveal
    /// travels past it. Anything else would read as text flickering back out.
    @Test("A glyph only ever grows more opaque")
    func theRampNeverGoesBackwards() {
        var previous = 0.0
        for step in 0 ... 40 {
            let opacity = WipeRenderer.opacity(ofGlyph: 20, at: Double(step))
            #expect(opacity >= previous, "opacity fell at frontier \(step)")
            previous = opacity
        }
        #expect(previous == 1, "and reaches full by the end of the sweep")
    }
}
