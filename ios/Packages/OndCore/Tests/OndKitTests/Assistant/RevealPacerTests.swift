@testable import OndKit
import Testing

@Suite("Reveal pacing")
struct RevealPacerTests {
    /// Releases until nothing more will come out, so a test can assert on where
    /// the reveal lands rather than on how many ticks it took. Bounded because
    /// a pacer that failed to advance would otherwise hang the suite rather
    /// than fail it.
    private func drained(_ pacer: consuming RevealPacer) -> RevealPacer {
        var pacer = pacer
        for _ in 0 ..< 1000 where !pacer.isSettled {
            pacer.release()
        }
        return pacer
    }

    /// The tail of an open stream may be half a word the next chunk completes,
    /// and "mech" turning into "mechanism" is a stutter nobody asked to read.
    @Test("A half-arrived word is withheld until more arrives")
    func aPartialWordIsWithheld() {
        var pacer = RevealPacer()
        pacer.append("The mech")

        for _ in 0 ..< 20 {
            pacer.release()
        }
        #expect(pacer.revealed == "The ")

        pacer.append("anism is slow.")
        for _ in 0 ..< 20 {
            pacer.release()
        }
        #expect(pacer.revealed == "The mechanism is ", "the last word waits on the close")
    }

    /// Closing is what makes the final word revealable — without it a reply
    /// would sit one word short of itself for ever.
    @Test("Closing releases the last word")
    func closingReleasesTheTail() {
        var pacer = RevealPacer()
        pacer.append("A longer exhale settles you.")
        pacer.close()

        #expect(drained(pacer).revealed == "A longer exhale settles you.")
    }

    /// The invariant the type exists for. Whatever the chunk boundaries were —
    /// mid-word, mid-whitespace, a lone newline — what is shown is a prefix of
    /// what arrived at every step, and exactly equal to it at the end.
    @Test("The reveal is always a prefix of what arrived, and ends equal to it")
    func theRevealIsAlwaysAPrefix() {
        let chunks = ["Nasal breath", "ing warms the air.", "\n\nTry ", "it now", "."]
        let whole = chunks.joined()

        var pacer = RevealPacer()
        for chunk in chunks {
            pacer.append(chunk)
            for _ in 0 ..< 3 {
                pacer.release()
                #expect(whole.hasPrefix(pacer.revealed), "showed text that never arrived")
            }
        }
        pacer.close()

        #expect(drained(pacer).revealed == whole)
    }

    /// The rule-based fallback answers in one chunk, so the backlog on its first
    /// tick is the whole reply. A quarter of that in a single frame is the wall
    /// of text the pacing exists to avoid.
    @Test("One tick never releases more than a burst")
    func oneTickIsBounded() {
        var pacer = RevealPacer()
        pacer.append(String(repeating: "word ", count: 200))
        pacer.close()

        pacer.release()
        #expect(pacer.revealed.count <= 64, "a whole reply never lands in one frame")
        #expect(!pacer.revealed.isEmpty)
    }

    /// A stream slower than the tick still moves: the floor is a word, so a
    /// trickle reveals rather than stalling until enough has piled up.
    @Test("A trickle still advances, a word at a time")
    func aTrickleStillAdvances() {
        var pacer = RevealPacer()

        pacer.append("one ")
        pacer.release()
        #expect(pacer.revealed == "one ")

        pacer.append("two ")
        pacer.release()
        #expect(pacer.revealed == "one two ")
    }

    /// Cancel's path: nobody is watching the pace, and what the store keeps must
    /// be what the server said rather than what the reveal had got round to.
    @Test("Flushing releases everything and settles")
    func flushingSettles() {
        var pacer = RevealPacer()
        pacer.append("The first part and the second part")
        pacer.release()

        pacer.flush()
        #expect(pacer.revealed == "The first part and the second part")
        #expect(pacer.isSettled)
    }

    /// A stream that closes having said nothing is settled immediately — the
    /// model's own empty-reply handling runs after the drain, so a pacer that
    /// never settled would strand it.
    @Test("An empty reply settles on close")
    func anEmptyReplySettles() {
        var pacer = RevealPacer()
        #expect(!pacer.isSettled, "nothing has said the stream is over")

        pacer.close()
        #expect(pacer.isSettled)
        #expect(pacer.revealed.isEmpty)
    }

    /// Retained indices have to survive both kinds of growth at once: chunks
    /// keep extending the source while ticks extend the separately stored
    /// revealed text. Repeating that transition catches a cursor that restarts
    /// from the reply's beginning or becomes detached after an append.
    @Test("Many interleaved chunks and releases preserve the exact reply")
    func interleavedGrowthKeepsTheReply() {
        let chunks = (0 ..< 400).map { "word\($0) 🌊 " } + ["finished"]
        let whole = chunks.joined()
        var pacer = RevealPacer()

        for chunk in chunks {
            pacer.append(chunk)
            pacer.release()
            #expect(whole.hasPrefix(pacer.revealed))
        }
        pacer.close()

        #expect(drained(pacer).revealed == whole)
    }

    /// A model delta is a valid string, but its boundary may still fall between
    /// the scalars of one visible character. Counting each new chunk keeps the
    /// cursor valid while the final String recombines the grapheme.
    @Test("A grapheme split across chunks remains intact")
    func splitGraphemeRemainsIntact() {
        var pacer = RevealPacer()
        pacer.append("Cafe")
        pacer.append("\u{301} is calm")
        pacer.close()

        #expect(drained(pacer).revealed == "Cafe\u{301} is calm")
    }
}
