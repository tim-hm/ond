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

        guard let surface = DeliverySurface(recorded: proto.surface) else {
            throw JourneyRepositoryError.malformedResponse(
                "session `\(id)` ran on unrecognised surface `\(proto.surface)`"
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
            surface: surface
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

private extension DeliverySurface {
    /// The surface a recorded session ran on — a different question from the
    /// one `DeliverySurface(proto:)` answers. Unset restores as full-screen:
    /// every session before the field ran that way. An unknown surface returns
    /// nil — the record is the person's own account, so no default is written
    /// for them — and the restore walk stops, per `docs/transport.md`.
    init?(recorded proto: Ond_V1_DeliverySurface) {
        if proto == .unspecified {
            self = .fullScreen
            return
        }

        guard let surface = DeliverySurface(proto: proto) else { return nil }

        self = surface
    }
}

/// Splits an instant into `google.protobuf.Timestamp`'s two fields. Returned
/// as a pair because SwiftProtobuf is OndAPI's dependency, not this target's,
/// so its types cannot be named here. The nanos are clamped: a rounding that
/// reached a full billion would encode a timestamp the server refuses.
/// Internal because `JourneyRepository`'s other mappings ride the same wire.
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

/// One of the wire's unsigned 32-bit counters. Refused rather than clamped: a
/// clamp on either end reports a session nobody did. `name` and `owner` feed
/// the log a skipped sync leaves behind.
func onTheWire(_ value: Int, _ name: String, of owner: UUID) throws -> UInt32 {
    guard let converted = UInt32(exactly: value) else {
        throw JourneyRepositoryError.malformedRequest(
            "\(owner) holds \(name) of \(value), which the wire cannot carry"
        )
    }
    return converted
}
