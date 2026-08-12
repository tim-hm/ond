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
        await recorder.note(.veryPleasant, at: after)

        #expect(await health.calls == [
            .wroteMood(.neutral, at: Self.tappedAt),
            .wroteMood(.veryPleasant, at: after),
        ])
    }

    /// Health's axis runs -1...1 with nought in the middle, and önd's five
    /// points sit evenly on it. Asserted as a whole rather than case by case:
    /// what matters is that the scale is centred, symmetric and reaches both
    /// ends, which no single case can say.
    @Test("The five points span Health's axis evenly, centred on nought")
    func theScaleIsEvenAndCentred() {
        #expect(Mood.allCases.map(\.valence) == [-1, -0.5, 0, 0.5, 1])
        #expect(Mood.neutral.valence == 0)
    }

    @Test("Every point says what it is")
    func everyPointIsNamed() {
        #expect(Mood.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(Set(Mood.allCases.map(\.title)).count == Mood.allCases.count)
    }
}
