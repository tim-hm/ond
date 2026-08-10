import Foundation
@testable import OndKit
import Testing

/// The dial's rules, over the catalogue the apps actually ship and routes shaped
/// like the ones `crates/migrate` seeds — so a slug that stops resolving fails
/// here rather than showing up as a stop that quietly vanished.
@Suite("Home as a dial")
struct HomeDialTests {
    private static func prescription(
        _ slug: String,
        goal: TechniqueGoal,
        surface: DeliverySurface = .fullScreen,
        minutes: Int = 5
    ) -> Prescription {
        Prescription(
            techniqueSlug: slug,
            goal: goal,
            surface: surface,
            duration: .seconds(minutes * 60)
        )
    }

    /// Occasions in the shape the server sends them, including the pair that
    /// differ only in surface — which is the distinction the dial has to keep.
    ///
    /// A representative set rather than a mirror of the seed: what these
    /// exercise is the dial's own rules, and pinning the working set is
    /// `the_seeded_occasions_resolve_as_decided`'s job on the other side.
    private static let occasions = [
        Occasion(
            slug: "before-a-presentation",
            name: "Before a presentation",
            summary: "Steady the nerves.",
            prescription: prescription("box-breathing", goal: .calm, minutes: 3)
        ),
        Occasion(
            slug: "through-this-meeting",
            name: "Through this meeting",
            summary: "Nothing on screen, nothing to hear.",
            prescription: prescription("coherent-breathing", goal: .calm, surface: .discreet)
        ),
        Occasion(
            slug: "winding-down",
            name: "Winding down",
            summary: "Long, slow out-breaths.",
            prescription: prescription("extended-exhale", goal: .sleep)
        ),
    ]

    private static let progression = [
        ProgressionStep(techniqueSlug: "box-breathing", note: "Start here."),
        ProgressionStep(techniqueSlug: "physiological-sigh", note: "The one that takes seconds."),
        ProgressionStep(techniqueSlug: "extended-exhale", note: "The lever underneath it."),
    ]

    private static let routes = Routes(occasions: occasions, progression: progression)

    private func session(_ slug: String) -> SessionRecord {
        SessionRecord(
            techniqueSlug: slug,
            startedAt: .now,
            duration: .seconds(120),
            cyclesCompleted: 4,
            breathCount: 8,
            completed: true
        )
    }

    private func dial(
        history: [SessionRecord] = [],
        hour: Int,
        routes: Routes = routes
    ) -> HomeDial {
        HomeDial(
            techniques: SeededCatalogue.techniques,
            routes: routes,
            history: history,
            hour: hour
        )
    }

    @Test("Somebody who has breathed nothing leads with the first rung of Start here")
    func firstRunLeadsWithTheProgression() {
        let lead = dial(hour: 14).lead

        #expect(lead?.band == .startHere)
        #expect(lead?.title == SeededCatalogue.technique("box-breathing").name)
        #expect(lead?.detail == "Start here.")
    }

    @Test("Somebody with history leads with the occasion the hour fits")
    func theHourPicksTheOccasion() {
        // 23:00 is `sleep` by `HomeSuggestion`, and one occasion borrows it.
        let lead = dial(history: [session("box-breathing")], hour: 23).lead

        #expect(lead?.title == "Winding down")
        #expect(lead?.goal == .sleep)
    }

    @Test("With no occasion for the hour, the lead is the rung they have reached")
    func theProgressionCatchesTheHoursThatRouteNowhere() {
        // 08:00 is `energy`, which no occasion here borrows.
        let lead = dial(history: [session("box-breathing")], hour: 8).lead

        #expect(lead?.title == SeededCatalogue.technique("physiological-sigh").name)
    }

    @Test("With no routes at all, the lead is still the hour's own suggestion")
    func aDeviceWithNoRoutesStillLeadsWithSomething() {
        let dial = dial(history: [session("box-breathing")], hour: 23, routes: .none)

        #expect(dial.lead != nil)
        #expect(dial.lead?.band == .everything)
        #expect(dial.lead?.goal == .sleep)
        // Every stop is a catalogue entry, and the whole catalogue is reachable.
        #expect(dial.stops.count == SeededCatalogue.techniques.count)
    }

    @Test("The lead is moved to the front of the dial rather than copied into it")
    func theLeadAppearsExactlyOnce() {
        let dial = dial(history: [session("box-breathing")], hour: 23)

        guard let lead = dial.lead else {
            Issue.record("the dial has no lead")
            return
        }

        #expect(dial.stops.filter { $0.id == lead.id }.count == 1)
        // It keeps its own band, and is the first stop of it — which is what a
        // surface showing one band at a time relies on.
        #expect(lead.band == .occasions)
        #expect(dial.stops.first { $0.band == .occasions }?.id == lead.id)
    }

    @Test("Occasions, Start here and the whole catalogue are each reachable by ticks")
    func everyBandIsOnTheDial() {
        let stops = dial(history: [session("box-breathing")], hour: 23).stops
        let bands = Set(stops.map(\.band))

        #expect(bands == Set(DialBand.allCases))
        #expect(stops.filter { $0.band == .everything }.count == SeededCatalogue.techniques.count)
        #expect(stops.filter { $0.band == .occasions }.count == Self.occasions.count)
    }

    @Test("The routed dial is the moments and the rungs, lead first, without the catalogue")
    func theRoutedDialLeavesTheCatalogueOut() {
        let dial = dial(history: [session("box-breathing")], hour: 23)

        #expect(dial.routed.first?.id == dial.lead?.id)
        #expect(!dial.routed.contains { $0.band == .everything })
        #expect(dial.routed.count == Self.occasions.count + Self.progression.count)
    }

    @Test("With no routes at all, the routed dial is the catalogue rather than nothing")
    func theRoutedDialNeverEmpties() {
        let dial = dial(history: [session("box-breathing")], hour: 23, routes: .none)

        #expect(dial.routed.count == SeededCatalogue.techniques.count)
    }

    /// The ordinary case for most of a working day, not an edge: no seeded
    /// occasion borrows `energy` or `focus`, so the morning and the afternoon
    /// route nowhere, and a returning person who has breathed every rung falls
    /// through to the catalogue. A dial that then filtered the catalogue out
    /// would be focused on a stop it does not draw.
    @Test("A lead that fell through to the catalogue is still on the routed dial")
    func theRoutedDialKeepsALeadItWouldOtherwiseFilterOut() {
        let breathed = Self.progression.map { session($0.techniqueSlug) }
        let dial = dial(history: breathed, hour: 8)

        guard let lead = dial.lead else {
            Issue.record("the dial has no lead")
            return
        }

        #expect(lead.band == .everything)
        #expect(dial.routed.first?.id == lead.id)
        // Every route, and the promoted lead, and nothing else — a promotion
        // that dropped a route on the way would satisfy the checks above.
        #expect(dial.routed.count == Self.occasions.count + Self.progression.count + 1)
        #expect(dial.routed.dropFirst().allSatisfy { $0.band != .everything })
    }

    /// The invariant `HomeDialView.rebuild()` rests on: it resets the focus to
    /// the lead and hands the picker `routed`, so a lead outside `routed` is a
    /// dial focused on a row it does not draw.
    @Test("The lead is always on the routed dial, whichever rule chose it")
    func theLeadIsAlwaysRouted() {
        let breathed = Self.progression.map { session($0.techniqueSlug) }

        for hour in 0 ..< 24 {
            for history in [[], [session("box-breathing")], breathed] {
                let dial = dial(history: history, hour: hour)
                #expect(dial.routed.contains { $0.id == dial.lead?.id })
            }
        }
    }

    /// Each band stays in one piece. Lifting the lead alone to the front of a
    /// fixed band order splits its own band around the others, and the first run
    /// is exactly that case — the lead is rung one, and the rest of the course
    /// would sit below every occasion.
    @Test("A band is contiguous, and the lead's band leads")
    func theLeadsBandComesWithIt() {
        let stops = dial(hour: 14).stops

        #expect(stops.first?.band == .startHere)
        #expect(stops.prefix(Self.progression.count).allSatisfy { $0.band == .startHere })

        // One run per band. A band that appears, stops, and appears again is a
        // band that was split around another.
        let runs = stops.map(\.band).reduce(into: [DialBand]()) { runs, band in
            if runs.last != band {
                runs.append(band)
            }
        }
        #expect(runs.count == Set(stops.map(\.band)).count)
    }

    @Test("A discreet occasion keeps its surface, and everything else is full screen")
    func theDiscreetSurfaceSurvivesTheFlattening() {
        let stops = dial(hour: 14).stops
        let discreet = stops.filter { $0.surface == .discreet }

        #expect(discreet.map(\.title) == ["Through this meeting"])
        // The same technique reached any other way makes no such promise.
        #expect(
            stops.contains {
                $0.band == .everything && $0.technique.slug == "coherent-breathing"
                    && $0.surface == .fullScreen
            }
        )
    }

    @Test("A route naming a technique the catalogue does not hold is not a stop")
    func anUnresolvableRouteIsDropped() {
        let ghost = Routes(
            occasions: [
                Occasion(
                    slug: "ghost",
                    name: "Ghost",
                    summary: "",
                    prescription: Self.prescription("no-such-technique", goal: .calm)
                ),
            ],
            progression: [ProgressionStep(techniqueSlug: "also-missing", note: "")]
        )
        let stops = dial(hour: 14, routes: ghost).stops

        #expect(!stops.contains { $0.band == .occasions })
        #expect(!stops.contains { $0.band == .startHere })
    }

    @Test("An occasion's dose stretches a cyclic technique towards the length it asks for")
    func theDoseFitsWholeCyclesIntoTheAskedForLength() {
        let coherent = SeededCatalogue.technique("coherent-breathing")
        let asked = Duration.seconds(300)
        let prescription = Self.prescription("coherent-breathing", goal: .calm, minutes: 5)

        guard let dose = prescription.dose(for: coherent) else {
            Issue.record("a single-stage cyclic technique should take a dose")
            return
        }

        let played = coherent.dialled(with: dose).plannedDuration
        let cycle = coherent.stages[0].cycleDuration
        // Whole cycles only, so the fit is within half a breath either way.
        #expect(abs(played.milliseconds - asked.milliseconds) <= cycle.milliseconds / 2)
    }

    @Test("A staged protocol keeps its own length rather than being stretched")
    func aStagedTechniqueTakesNoDose() {
        let staged = SeededCatalogue.technique("wim-hof-rounds")
        let prescription = Self.prescription("wim-hof-rounds", goal: .energy, minutes: 2)

        #expect(prescription.dose(for: staged) == nil)
    }

    @Test("The rung led with advances as each one is breathed")
    func theProgressionIsReadFromTheirOwnHistory() {
        // 08:00 routes to no occasion here, so the lead is the progression's.
        let two = [session("box-breathing"), session("physiological-sigh")]
        let lead = dial(history: two, hour: 8).lead

        #expect(lead?.technique.slug == "extended-exhale")
        #expect(dial(history: [], hour: 8).lead?.technique.slug == "box-breathing")
    }

    @Test("Every stop carries a distinct identity, so the dial can be scrolled to one")
    func stopsAreUniquelyIdentified() {
        let stops = dial(history: [session("box-breathing")], hour: 23).stops

        #expect(Set(stops.map(\.id)).count == stops.count)
    }

    @Test("A catalogue sent with a repeated slug is one stop, not two sharing an identity")
    func aRepeatedSlugIsOneStop() {
        let doubled = SeededCatalogue.techniques + [SeededCatalogue.technique("box-breathing")]
        let stops = HomeDial(techniques: doubled, routes: .none, history: [], hour: 14).stops

        #expect(Set(stops.map(\.id)).count == stops.count)
        #expect(stops.count == SeededCatalogue.techniques.count)
    }

    /// The row states a length and the button beneath it plays one; the two are
    /// the same number or the screen is lying. `HomeDialView` starts a stop from
    /// `dose`, so pinning `dose` and `duration` together is what pins that.
    @Test("A dialled exercise states the length this person set, and an occasion its own")
    func thePersonsOwnDialsReachTheStatedLength() {
        let coherent = SeededCatalogue.technique("coherent-breathing")
        var longer = coherent.curatedOverrides
        longer.stageCycles = [coherent.stages[0].cycles * 3]

        let stops = HomeDial(
            techniques: SeededCatalogue.techniques,
            routes: Self.routes,
            history: [session("box-breathing")],
            hour: 14,
            dialled: [coherent.slug: longer]
        ).stops

        let catalogued = stops
            .first { $0.band == .everything && $0.technique.slug == coherent.slug }
        #expect(catalogued?.dose == longer)
        #expect(catalogued?.duration == coherent.dialled(with: longer).plannedDuration)

        // The occasion over the same technique overrules it — a prescription is
        // an offer about a length, and answering with a different one is not it.
        let occasion = stops.first { $0.title == "Through this meeting" }
        #expect(occasion?.dose != longer)
        #expect(occasion?.duration != catalogued?.duration)
    }
}
