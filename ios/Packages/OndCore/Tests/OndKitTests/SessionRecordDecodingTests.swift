import Foundation
import OndAPI
@testable import OndKit
import Testing

/// Reading a session the server holds back onto this device — the restore
/// path that stops a streak vanishing with a reinstall. `surface` is not
/// display-only: a discreet session earns no Mindful Minutes, so a restored
/// record naming a surface this build cannot read is a claim about Health,
/// not a label.
@Suite("Reading a stored session back off the wire")
struct SessionRecordDecodingTests {
    private static func protoRecord(
        surface: Ond_V1_DeliverySurface = .fullScreen
    ) -> Ond_V1_SessionRecord {
        var message = Ond_V1_SessionRecord()
        message.clientSessionID = "8A7B0F6E-4C1D-4E2A-9B3F-0D5C6E7A8B90"
        message.techniqueSlug = "box-breathing"
        message.startedAt.seconds = 1_754_900_000
        message.durationMs = 240_000
        message.cyclesCompleted = 4
        message.breathCount = 8
        message.completed = true
        message.surface = surface
        return message
    }

    @Test("A session comes back on the surface it ran on")
    func decodesTheSurfaceItRanOn() throws {
        let ran: [(Ond_V1_DeliverySurface, DeliverySurface)] = [
            (.fullScreen, .fullScreen),
            (.discreet, .discreet),
        ]

        for (wire, surface) in ran {
            let record = try SessionRecord(proto: Self.protoRecord(surface: wire))
            #expect(record.surface == surface)
        }
    }

    /// The legacy half, and the only value here that may be defaulted: every
    /// session recorded before the field existed ran full-screen, so restoring
    /// one as anything else would invent a discretion nobody asked for.
    @Test("A session from before the surface existed comes back full-screen")
    func defaultsAnUnsetSurface() throws {
        let record = try SessionRecord(proto: Self.protoRecord(surface: .unspecified))

        #expect(record.surface == .fullScreen)
    }

    /// A newer server's surface: something this build has no name for, in
    /// somebody's own account of what they did. The page fails, stopping the
    /// restore walk until a build that knows the surface — the cost
    /// `docs/transport.md` books for every enum here. Guessing would write this
    /// app's answer into their history, indistinguishable from theirs.
    @Test("A surface this build cannot name fails the page rather than guessing")
    func refusesAnUnreadableSurface() {
        #expect(throws: JourneyRepositoryError.self) {
            try SessionRecord(proto: Self.protoRecord(surface: .UNRECOGNIZED(7)))
        }
    }
}
