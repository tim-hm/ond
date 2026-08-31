import Foundation
@testable import OndKit
import Testing

/// What the mood check records, the scale it records it on, and whether
/// it is asked for at all. The scale is worth pinning because a valence
/// is the whole of what a sample carries: get the mapping wrong and every
/// reading is silently on somebody else's axis, in a store this app never
/// reads back to notice.
@Suite("Mood check")
@MainActor
struct MoodRecorderTests {
    private static let tappedAt = Date(timeIntervalSince1970: 1_777_000_000)

    private let health = SpyHealthStore()

    /// Two readings around one practice, which is the pair the summary reads
    /// back and the only reason the "before" screen exists at all. Each carries
    /// the moment it was tapped, and nothing else reaches Health — no read, no
    /// minutes, no grant call the recorder had to remember.
    @Test("Before and after are two samples, not one that was revised")
    func aPairIsTwoSamples() async {
        let recorder = MoodRecorder(store: health)
        let after = Self.tappedAt.addingTimeInterval(300)

        await recorder.note(.neutral, at: Self.tappedAt)
        await recorder.note(.pleasant, at: after)

        #expect(await health.calls == [
            .wroteMood(.neutral, at: Self.tappedAt),
            .wroteMood(.pleasant, at: after),
        ])
    }

    /// The five plain-language choices span Health's axis and keep an equal
    /// step between them. Asserted as a whole rather than case by case: what
    /// matters is that the scale stays centred and symmetric.
    @Test("The five points are evenly centred on nought")
    func theScaleIsEvenAndCentred() {
        #expect(Mood.allCases.map(\.valence) == [-1, -0.5, 0, 0.5, 1])
        #expect(Mood.neutral.valence == 0)
    }

    /// A grant is decided once per install, so asking again can only get the
    /// same answer — and the ask reaches the health daemon at the start of a
    /// session, which is the moment least able to spare it.
    @Test("A settled grant is asked about once, not once a session")
    func aSettledGrantIsAskedAboutOnce() async {
        let store = PromptingHealthStore(mayPrompt: false)
        let recorder = MoodRecorder(store: store)

        #expect(await recorder.writeMayPrompt() == false)
        #expect(await recorder.writeMayPrompt() == false)
        #expect(await store.asks == 1)
    }

    /// The opposite case, and the reason the answer above is the only one kept:
    /// an undecided grant is about to be decided by the very write that follows.
    @Test("An undecided grant is asked about every time")
    func anUndecidedGrantIsAskedAboutEveryTime() async {
        let store = PromptingHealthStore(mayPrompt: true)
        let recorder = MoodRecorder(store: store)

        #expect(await recorder.writeMayPrompt() == true)
        #expect(await recorder.writeMayPrompt() == true)
        #expect(await store.asks == 2)
    }

    /// The numerals the scale draws. Pinned to the order the cases are in,
    /// because the two ends label the row and a point numbered out of turn
    /// would put a name under the wrong end of it.
    @Test("The points are numbered one to five, in order")
    func everyPointIsNumbered() {
        #expect(Mood.allCases.map(\.position) == [1, 2, 3, 4, 5])
        #expect(Mood.lowest == Mood.allCases.first)
        #expect(Mood.highest == Mood.allCases.last)
    }

    @Test("Every point says what it is")
    func everyPointIsNamed() {
        #expect(Mood.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(Set(Mood.allCases.map(\.title)).count == Mood.allCases.count)
        #expect(Mood.allCases.map(\.title) == ["Bad", "Not good", "Okay", "Good", "Great"])
    }
}
