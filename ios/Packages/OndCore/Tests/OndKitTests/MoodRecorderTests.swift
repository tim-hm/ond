import Foundation
@testable import OndKit
import Testing

/// What the mood check records, the scale it records it on, and whether it is
/// asked for at all.
///
/// The scale is worth pinning because a valence is the whole of what a sample
/// carries: get the mapping wrong and every reading is silently on somebody
/// else's axis, in a store this app never reads back to notice.
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

    /// The three plain-language choices keep the middle of Health's axis and an
    /// equal step to either side. Asserted as a whole rather than case by case:
    /// what matters is that the scale stays centred and symmetric.
    @Test("The three points are evenly centred on nought")
    func theScaleIsEvenAndCentred() {
        #expect(Mood.allCases.map(\.valence) == [-0.5, 0, 0.5])
        #expect(Mood.neutral.valence == 0)
    }

    @Test("Every point says what it is")
    func everyPointIsNamed() {
        #expect(Mood.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(Set(Mood.allCases.map(\.title)).count == Mood.allCases.count)
        #expect(Mood.allCases.map(\.title) == ["Not good", "Okay", "Good"])
    }
}
