import Foundation

/// One resting-rate measurement: breaths counted over a minute, sitting still.
/// Deliberately not a second reading of the pause: that measures CO2 tolerance,
/// this the habitual pattern underneath, so the two move independently. Whole
/// breaths, because a person counting their own cannot resolve a fraction.
/// Recorded locally first; the id is the sync's idempotency key.
public struct RestingRate: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let breathsPerMinute: Int
    public let measuredAt: Date

    public init(id: UUID = UUID(), breathsPerMinute: Int, measuredAt: Date = .now) {
        self.id = id
        self.breathsPerMinute = breathsPerMinute
        self.measuredAt = measuredAt
    }
}

/// Somewhere to keep resting rates, on the device that counted them.
///
/// Non-throwing on the same terms as `BoltScoreRecording`: a failed local write
/// is nothing the person who just sat and counted can act on. Implementations
/// log and carry on.
public protocol RestingRateRecording: Sendable {
    func record(_ rate: RestingRate) async
    /// Every recorded rate, oldest first.
    func recordedRates() async -> [RestingRate]
}

public extension RestingRateRecording {
    /// The slowest rate this device knows about, or `nil` before the first
    /// count. Lowest is the personal best — the one place this measurement
    /// reads backwards from the pause beside it. Computed locally rather than
    /// read from the server, so the card is right in airplane mode.
    func lowest() async -> Int? {
        await recordedRates().map(\.breathsPerMinute).min()
    }
}

/// Rate history as one JSON file, beside the sessions and the pauses.
public actor FileRestingRateStore: RestingRateRecording, PersonalStore {
    private let file: JSONFileStore<RestingRate>

    /// - Parameter directory: where `resting-rates.json` lives. Application
    ///   Support by default, for the same reason sessions live there.
    public init(directory: URL = .applicationSupportDirectory) {
        file = JSONFileStore(
            directory: directory,
            fileName: "resting-rates.json",
            category: "resting-rate-store"
        )
    }

    public func record(_ rate: RestingRate) async {
        file.save(file.load() + [rate])
    }

    public func recordedRates() async -> [RestingRate] {
        file.load()
    }

    public func erase() async {
        file.erase()
    }
}
