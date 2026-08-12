import Foundation

extension DialStop {
    /// The catalogue keyed by slug, which every band below resolves against.
    ///
    /// First slug wins, which the catalogue's own uniqueness makes moot — stated
    /// only because `Dictionary(uniqueKeysWithValues:)` would trap on a duplicate
    /// the server is free to send.
    static func indexed(_ techniques: [Technique]) -> [String: Technique] {
        Dictionary(techniques.map { ($0.slug, $0) }) { first, _ in first }
    }

    /// The named moments, in seeded order.
    ///
    /// An occasion naming an exercise this build no longer holds is dropped
    /// rather than drawn: a route nobody can breathe is not a stop, and a row
    /// that opened onto nothing would be worse than a row that was never there.
    ///
    /// - Parameters:
    ///   - routes: the routing layer as it last arrived. `Routes.none` answers
    ///     with nothing, which is the supported state a device that has never
    ///     reached the server is in.
    ///   - bySlug: the catalogue, from ``indexed(_:)``.
    ///   - dialled: what this person dialled themselves, keyed by slug. Carried
    ///     even though an occasion's prescription overrules it, because
    ///     `DialStop`'s init is the one place that precedence is stated.
    static func occasions(
        of routes: Routes,
        resolvedBy bySlug: [String: Technique],
        dialled: [String: TechniqueOverrides]
    ) -> [DialStop] {
        routes.occasions.compactMap { occasion in
            bySlug[occasion.prescription.techniqueSlug].map { technique in
                DialStop(
                    technique: technique,
                    origin: .occasion(occasion),
                    band: .occasions,
                    saved: dialled[technique.slug]
                )
            }
        }
    }

    /// The Start here progression, in curated order and on the same drop rule.
    static func steps(
        of routes: Routes,
        resolvedBy bySlug: [String: Technique],
        dialled: [String: TechniqueOverrides]
    ) -> [DialStop] {
        routes.progression.compactMap { step in
            bySlug[step.techniqueSlug].map { technique in
                DialStop(
                    technique: technique,
                    origin: .step(step),
                    band: .startHere,
                    saved: dialled[technique.slug]
                )
            }
        }
    }

    /// Exercises standing for themselves, in the order the list arrived in.
    ///
    /// - Parameter band: `.yours` for what this person composed, `.everything`
    ///   for the catalogue. The caller decides, because the band is which list a
    ///   technique arrived in and nothing on the technique answers it —
    ///   `DialStop.id(of:)` reads `Technique.origin` to reach the same answer
    ///   from the other end, and `everyStandaloneStopCarriesTheIdItsTechniqueAnswersWith`
    ///   is what holds the two together.
    static func standalone(
        _ techniques: [Technique],
        in band: DialBand,
        dialled: [String: TechniqueOverrides]
    ) -> [DialStop] {
        techniques.map { technique in
            DialStop(
                technique: technique,
                origin: .technique,
                band: band,
                saved: dialled[technique.slug]
            )
        }
    }
}
