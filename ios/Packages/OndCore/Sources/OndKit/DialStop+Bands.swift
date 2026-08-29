import Foundation

extension DialStop {
    /// The catalogue keyed by slug, which every band below resolves against.
    ///
    /// First slug wins, which the catalogue's own uniqueness makes moot —
    /// stated only because `Dictionary(uniqueKeysWithValues:)` would trap on a
    /// duplicate the server is free to send.
    static func indexed(_ techniques: [Technique]) -> [String: Technique] {
        Dictionary(techniques.map { ($0.slug, $0) }) { first, _ in first }
    }

    /// The named moments, in seeded order. An occasion naming an exercise this
    /// build no longer holds is dropped rather than drawn: a route nobody can
    /// breathe is not a stop. `dialled` is carried even though an occasion's
    /// prescription overrules it, because `DialStop`'s init is the one place
    /// that precedence is stated.
    static func occasions(
        of occasionCatalogue: OccasionCatalogue,
        resolvedBy bySlug: [String: Technique],
        dialled: [String: TechniqueOverrides]
    ) -> [DialStop] {
        deduplicated(occasionCatalogue.occasions.compactMap { occasion in
            bySlug[occasion.prescription.techniqueSlug].map { technique in
                DialStop(
                    technique: technique,
                    origin: .occasion(occasion),
                    band: .occasions,
                    saved: dialled[technique.slug]
                )
            }
        })
    }

    /// Exercises standing for themselves, in the order the list arrived in.
    /// - Parameter band: `.yours` or `.everything` — the caller decides,
    ///   because the band is which list a technique arrived in and nothing on
    ///   the technique answers it. `DialStop.id(of:)` reaches the same answer
    ///   from the other end, and a test holds the two together.
    static func standalone(
        _ techniques: [Technique],
        in band: DialBand,
        dialled: [String: TechniqueOverrides]
    ) -> [DialStop] {
        deduplicated(techniques.map { technique in
            DialStop(
                technique: technique,
                origin: .technique,
                band: band,
                saved: dialled[technique.slug]
            )
        })
    }

    /// The first stop under each id, in the order they were built. A duplicate
    /// slug is something the server is documented as free to send, and nothing
    /// coalesces one in a route list — two stops sharing an id is a `ForEach`
    /// with undefined behaviour rather than a row drawn twice.
    private static func deduplicated(_ stops: [DialStop]) -> [DialStop] {
        var seen: Set<DialStop.ID> = []
        return stops.filter { seen.insert($0.id).inserted }
    }
}
