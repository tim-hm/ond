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
    /// Remembers what reached Health, and answers nothing — a mood is written,
    /// never read.
    private actor SpyHealthStore: HealthStore {
        private(set) var moods: [(Mood, Date)] = []
        private(set) var otherCalls = 0

        func requestReadAuthorization() async {
            otherCalls += 1
        }

        func requestWriteAuthorization() async {
            otherCalls += 1
        }

        func restingHeartRate(from _: Date, to _: Date) async -> [DailyQuantity] {
            otherCalls += 1
            return []
        }

        func heartRateVariability(from _: Date, to _: Date) async -> [DailyQuantity] {
            otherCalls += 1
            return []
        }

        func respiratoryRate(from _: Date, to _: Date) async -> [DailyQuantity] {
            otherCalls += 1
            return []
        }

        func writeMindfulSession(from _: Date, to _: Date) async {
            otherCalls += 1
        }

        func writeMood(_ mood: Mood, at date: Date) async {
            moods.append((mood, date))
        }
    }

    private static let tappedAt = Date(timeIntervalSince1970: 1_777_000_000)

    private let health = SpyHealthStore()

    @Test("A noted mood reaches Health at the moment it was tapped, and nothing else does")
    func noteWritesTheMood() async {
        let recorder = MoodRecorder(store: health)

        await recorder.note(.pleasant, at: Self.tappedAt)

        let moods = await health.moods
        #expect(moods.count == 1)
        #expect(moods.first?.0 == .pleasant)
        #expect(moods.first?.1 == Self.tappedAt)
        #expect(
            await health.otherCalls == 0,
            "the write asks for its own grant — see HealthStore.writeMood"
        )
    }

    /// Two readings around one practice, which is the pair the summary reads
    /// back and the only reason the "before" screen exists at all.
    @Test("Before and after are two samples, not one that was revised")
    func aPairIsTwoSamples() async {
        let recorder = MoodRecorder(store: health)
        let after = Self.tappedAt.addingTimeInterval(300)

        await recorder.note(.neutral, at: Self.tappedAt)
        await recorder.note(.veryPleasant, at: after)

        let moods = await health.moods
        #expect(moods.map(\.0) == [.neutral, .veryPleasant])
        #expect(moods.map(\.1) == [Self.tappedAt, after])
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

    /// The trap this pins: `UserDefaults.bool(forKey:)` answers false for an
    /// absent key, which for a preference that ships on would silence the
    /// feature for every install until somebody found the switch and flipped it
    /// twice.
    @Test("A fresh install is asked; switching off survives a relaunch")
    func theCheckIsOnUntilItIsTurnedOff() throws {
        let defaults =
            try #require(UserDefaults(suiteName: "mood-check-tests.\(UUID().uuidString)"))

        #expect(SessionSettings(defaults: defaults).asksHowYouFeel)

        SessionSettings(defaults: defaults).asksHowYouFeel = false

        #expect(!SessionSettings(defaults: defaults).asksHowYouFeel)
    }
}
