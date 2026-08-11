import Foundation
import OndAPI

/// `SessionRecord` on the wire, split from `JourneyRepository` where every
/// other mapping lives only because the record maps in both directions — it is
/// what the client sends up *and* what `GetJourney` hands back — and the pair
/// outgrew the repository's file.
extension SessionRecord {
    init(proto: Ond_V1_SessionRecord) throws {
        guard let id = UUID(uuidString: proto.clientSessionID) else {
            throw JourneyRepositoryError.malformedResponse(
                "`\(proto.clientSessionID)` is not a session id"
            )
        }

        self.init(
            id: id,
            techniqueSlug: proto.techniqueSlug,
            startedAt: proto.startedAt.date,
            duration: .milliseconds(proto.durationMs),
            cyclesCompleted: Int(proto.cyclesCompleted),
            breathCount: Int(proto.breathCount),
            completed: proto.completed,
            occasionSlug: proto.hasOccasionSlug ? proto.occasionSlug : nil,
            // Unlike a route, a record's unreadable surface degrades safely:
            // full-screen is what every session was before the field existed,
            // and nothing here is a promise about how loudly anything will run.
            surface: DeliverySurface(proto: proto.surface) ?? .fullScreen
        )
    }

    /// Throwing, unlike the decoders it sits beside, because every number here
    /// arrives from `sessions.json` — a file `SessionRecord`'s own doc promises
    /// a person can read, which a backup can restore and `JSONFileStore.load()`
    /// range-checks not at all — and lands in an unsigned 32-bit field.
    var proto: Ond_V1_SessionRecord {
        get throws {
            var message = Ond_V1_SessionRecord()
            message.clientSessionID = id.uuidString
            message.techniqueSlug = techniqueSlug
            let started = try timestampParts(startedAt)
            message.startedAt.seconds = started.seconds
            message.startedAt.nanos = started.nanos
            message.durationMs = try onTheWire(durationMs, "a duration in ms", of: id)
            message.cyclesCompleted = try onTheWire(cyclesCompleted, "a cycle count", of: id)
            message.breathCount = try onTheWire(breathCount, "a breath count", of: id)
            message.completed = completed
            if let occasionSlug {
                message.occasionSlug = occasionSlug
            }
            message.surface = switch surface {
            case .fullScreen: .fullScreen
            case .discreet: .discreet
            }
            return message
        }
    }
}

/// Splits an instant into the two fields `google.protobuf.Timestamp` carries.
///
/// Returned as a pair and assigned through the message's own properties rather
/// than built as a `Google_Protobuf_Timestamp`: SwiftProtobuf is OndAPI's
/// dependency and not this target's, so its types can be read through a
/// generated message but never named here. That is the module boundary working
/// rather than an obstacle to it.
///
/// The nanoseconds are clamped, because a rounding that reached a full billion
/// would encode a timestamp the server refuses. Past the seconds guard the
/// fraction is known to be in `0 ..< 1`, so they cannot overflow.
///
/// Internal rather than fileprivate: `JourneyRepository`'s bolt and
/// resting-rate mappings ride the same wire.
func timestampParts(_ instant: Date) throws -> (seconds: Int64, nanos: Int32) {
    let interval = instant.timeIntervalSince1970
    let whole = interval.rounded(.down)

    guard let seconds = Int64(exactly: whole) else {
        throw JourneyRepositoryError.malformedRequest(
            "\(instant) is not an instant the wire can carry"
        )
    }

    return (
        seconds: seconds,
        nanos: min(999_999_999, Int32(((interval - whole) * 1_000_000_000).rounded()))
    )
}

/// One of the wire's unsigned 32-bit counters.
///
/// Refused rather than clamped: a clamp on either end reports a session nobody
/// did, and a person's own figures are the ones they are most likely to believe.
///
/// - Parameters:
///   - value: the count as this device stores it, in `Int`.
///   - name: what it counts, for the log a skipped sync leaves behind.
///   - owner: the record it belongs to, so the log names something findable in
///     the file.
func onTheWire(_ value: Int, _ name: String, of owner: UUID) throws -> UInt32 {
    guard let converted = UInt32(exactly: value) else {
        throw JourneyRepositoryError.malformedRequest(
            "\(owner) holds \(name) of \(value), which the wire cannot carry"
        )
    }
    return converted
}
