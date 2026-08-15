import Foundation
import OndAPI

/// How `ListRoutes` comes off the wire.
///
/// Beside the domain types rather than inside `TechniqueRepository`, where the
/// catalogue's own decoders sit: a route's rejection rules are one argument,
/// and it is best read in one place rather than at the end of a longer file.
extension OccasionCatalogue {
    /// One bad entry fails the whole response, exactly as one bad technique
    /// fails the catalogue. Dropping it instead would leave a person ticking
    /// past a gap where a moment used to be, with nothing anywhere saying so.
    init(proto: Ond_V1_ListRoutesResponse) throws {
        try self.init(
            occasions: proto.occasions.map { try Occasion(proto: $0) },
            progression: proto.progression.map(ProgressionStep.init(proto:))
        )
    }
}

extension Occasion {
    init(proto: Ond_V1_Occasion) throws {
        // The contract says the prescription is always set, so its absence is a
        // message that never arrived rather than an occasion with no route —
        // and proto3 would otherwise hand back a zero-valued one that decodes as
        // an unnamed technique.
        guard proto.hasPrescription else {
            throw TechniqueRepositoryError.malformedResponse(
                "occasion `\(proto.slug)` carries no prescription"
            )
        }

        try self.init(
            slug: proto.slug,
            name: proto.name,
            summary: proto.summary,
            prescription: Prescription(proto: proto.prescription, occasion: proto.slug)
        )
    }
}

extension Prescription {
    /// - Parameter occasion: the slug of the occasion being decoded, named only
    ///   so a failure says which moment is broken — a prescription has no
    ///   identity of its own.
    init(proto: Ond_V1_Prescription, occasion: String) throws {
        guard let goal = TechniqueGoal(proto: proto.goal) else {
            throw TechniqueRepositoryError.malformedResponse(
                "occasion `\(occasion)` has unrecognised goal `\(proto.goal)`"
            )
        }

        guard let surface = DeliverySurface(proto: proto.surface) else {
            throw TechniqueRepositoryError.malformedResponse(
                "occasion `\(occasion)` has unrecognised surface `\(proto.surface)`"
            )
        }

        // Zero is the proto default and so what a server predating the field
        // sends. Same rule as the catalogue's round count: a value this app
        // cannot represent — and an occasion asking for no time is one — is a
        // decode failure rather than a silent guess.
        guard proto.durationMs > 0 else {
            throw TechniqueRepositoryError.malformedResponse(
                "occasion `\(occasion)` asks for no time at all"
            )
        }

        guard proto.phaseDurationsMs.allSatisfy({ $0 > 0 }) else {
            throw TechniqueRepositoryError.malformedResponse(
                "occasion `\(occasion)` carries a zero-length protocol phase"
            )
        }

        self.init(
            techniqueSlug: proto.techniqueSlug,
            goal: goal,
            surface: surface,
            // The one nil on this boundary that is degraded rather than
            // refused: an unreadable surface loses the whole response two
            // guards up, where an unreadable register loses a tone of voice —
            // and a route dropped over that would take a working exercise off
            // the board to avoid saying "Breathe in" instead of something
            // warmer.
            register: CopyRegister(proto: proto.register) ?? .plain,
            duration: .milliseconds(proto.durationMs),
            phaseDurations: proto.phaseDurationsMs.map(Duration.milliseconds),
            safetyNote: proto.safetyNote
        )
    }
}

extension CopyRegister {
    /// The two wire values a client cannot read say different things about a
    /// register and the same thing about a surface, which is why this returns
    /// nil for one of them where `DeliverySurface`'s returns nil for both.
    ///
    /// `UNSPECIFIED` is the field a server predating the register leaves empty,
    /// and plain is what this app spoke before it existed — a fact about the
    /// contract's history, settled here rather than by every caller. A register
    /// this build has no name for is a newer server naming a tone of voice, and
    /// what that costs depends on what is being decoded, so the caller says.
    init?(proto: Ond_V1_CopyRegister) {
        switch proto {
        case .playful: self = .playful
        case .plain, .unspecified: self = .plain
        case .UNRECOGNIZED: return nil
        }
    }
}

extension DeliverySurface {
    /// Returns nil for `UNSPECIFIED` and for any surface added after this app
    /// shipped. Both mean the same thing to a running client — a promise about
    /// how loudly a session runs that it cannot keep — and the one route it
    /// must not degrade to is the noisy one.
    init?(proto: Ond_V1_DeliverySurface) {
        switch proto {
        case .fullScreen: self = .fullScreen
        case .discreet: self = .discreet
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

extension ProgressionStep {
    /// Total, like the foundations decoder: both fields are strings this app
    /// only ever displays or resolves against the catalogue, so there is no
    /// value here it could fail to represent. A step naming a technique the
    /// catalogue does not hold is dropped where the two are joined, not here.
    init(proto: Ond_V1_ProgressionStep) {
        self.init(techniqueSlug: proto.techniqueSlug, note: proto.note)
    }
}
