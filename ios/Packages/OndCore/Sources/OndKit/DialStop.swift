import Foundation

/// The kinds of thing the dial holds, in the order it ticks through them.
///
/// A band is a promise about what a stop *is* — a named moment, a rung of a
/// course, an exercise somebody wrote, an exercise standing for itself. The
/// recommendation is none of those: it is one of them, moved to the front. A
/// band of its own for it put an extra kind of thing in one scroll and left the
/// reader holding them all; the lead is a position now, not a zone.
///
/// What a surface does with the bands is its own decision, and the case order
/// here is tick order rather than any surface's reading order — a screen that
/// wants Start here before the occasions says so itself.
public enum DialBand: String, Sendable, Hashable, CaseIterable {
    /// The named moments — `OccasionCatalogue.occasions`, in seeded order.
    case occasions

    /// The curated ordering for somebody who has picked no goal at all.
    case startHere

    /// What this person composed themselves, in the order the server keeps them.
    ///
    /// Its own band rather than folded into `everything`, because "an exercise
    /// you wrote" is a different promise from "an exercise this app ships" —
    /// the first is somewhere you go deliberately, and it is the one band whose
    /// stops nobody but its author can see.
    case yours

    /// The whole catalogue, so nothing the app has is unreachable from home.
    case everything
}

/// One thing the dial can come to rest on.
///
/// Every stop resolves to a technique, whichever band it came from: a route
/// nobody can breathe is not a stop, and keeping the technique on the value is
/// what lets one Begin underneath the dial serve all three bands.
public struct DialStop: Sendable, Hashable, Identifiable {
    /// What this stop was before the dial flattened it, which is what decides
    /// the words shown and the promise made.
    public enum Origin: Sendable, Hashable {
        /// A named moment, with the goal, surface and session it prescribes.
        case occasion(Occasion)
        /// A rung of Start here. Its position is the dial's own — the band it
        /// sits in is already in curated order.
        case step(ProgressionStep)
        /// A catalogue entry or an authored one, standing for itself. Which of
        /// the two is the band's to say; nothing about how a stop is drawn or
        /// played turns on it, because `Technique.origin` already carries the
        /// distinction for anything that needs it.
        case technique
    }

    public let technique: Technique
    public let origin: Origin
    public let band: DialBand

    /// The technique as this stop will actually play it.
    ///
    /// Kept rather than discarded, which it was: the init built it to read a
    /// length off and threw the value away, so both home layouts called
    /// `dialled(with:)` again on every layout pass to draw the figure. Worse than
    /// the wasted rebuilds, two resolutions of one stop could disagree — the
    /// length printed on a card came from here and the rhythm drawn beside it from
    /// there.
    public let dialled: Technique

    /// How long this stop actually takes — read off the dialled technique
    /// rather than off the prescription, because an occasion asking for five
    /// minutes of something four minutes long gets four.
    public let duration: Duration

    /// Stored rather than computed, all of them, because the layouts over a stop
    /// are drawn on every pass and `dialled(with:)` rebuilds a whole technique to
    /// answer. A stop is built once per rebuild; this is the work that belongs
    /// there.
    ///
    /// - Parameter saved: what this person dialled for `technique` themselves,
    ///   or nil where they took it as curated. An occasion overrules it — that
    ///   is what the word prescription means, and "a minute to come down from a
    ///   spike" is an offer about a length. Everywhere else it wins, and it has
    ///   to reach here rather than only the Begin: the row states a length, and
    ///   a length stated is a length the button owes.
    init(technique: Technique, origin: Origin, band: DialBand, saved: TechniqueOverrides?) {
        self.technique = technique
        self.origin = origin
        self.band = band

        dialled = switch origin {
        case let .occasion(occasion): occasion.prescription.dialled(technique)
        case .step, .technique: technique.dialled(with: saved)
        }
        duration = dialled.plannedDuration
    }

    /// Unique across the whole dial, which the technique's slug is not: Start
    /// here names five of the catalogue's twelve, so the same exercise is a stop
    /// in two bands and a card's identity needs to tell them apart.
    public var id: String {
        Self.id(in: band, key: key)
    }

    /// The id this exercise's own card carries, answerable before any card
    /// exists.
    ///
    /// Two callers need it and neither can wait for a stop: the composer stars an
    /// exercise the moment somebody writes one, and an exercise's own screen
    /// stars whatever it is showing. Written here rather than assembled at those
    /// call sites, and `id` above goes through the same formatter, because the
    /// strings have to be equal — a second copy of the format is free to drift,
    /// and the symptom would be a star that silently pins nothing.
    ///
    /// The band is read off `origin`, which is the same question `init` answers by
    /// which list a technique arrived in: this person's own are handed to
    /// `authored:` and become `yours`, the catalogue is handed to `techniques:`
    /// and becomes `everything`. Nothing enforces that correspondence, so
    /// `everyStandaloneStopCarriesTheIdItsTechniqueAnswersWith` does.
    ///
    /// An occasion or a rung naming the same exercise is deliberately not what
    /// this answers with. A star from an exercise's own screen is about the
    /// exercise and not about the moment that happens to prescribe it, and an id
    /// tied to a route would go inert the day the server stopped sending it.
    public static func id(of technique: Technique) -> ID {
        id(in: technique.origin == .personal ? .yours : .everything, key: technique.slug)
    }

    /// Every id a card standing for this exercise could carry, `id(of:)` among
    /// them.
    ///
    /// What a star control outside home has to ask, because `id(of:)` alone cannot
    /// answer "is this exercise on Home's shelf". An install can still hold a
    /// persisted `startHere/box-breathing` star, and a toolbar comparing only
    /// against `everything/box-breathing` would draw an empty star over that
    /// exercise, then shelve a second identical row when it was tapped.
    ///
    /// The three bands keyed by the technique's own slug, and deliberately not the
    /// occasions: an occasion is keyed by the moment, and "Winding down" is a
    /// different promise from the exercise it prescribes — starring the moment is
    /// not starring the exercise, and a control that cleared one by pressing the
    /// other would take away something nobody pointed at.
    public static func ids(standingFor technique: Technique) -> Set<ID> {
        [
            id(in: .yours, key: technique.slug),
            id(in: .startHere, key: technique.slug),
            id(in: .everything, key: technique.slug),
        ]
    }

    /// This exercise as a stop standing for itself.
    ///
    /// The one way to build a stop from outside this module, and it exists for
    /// the hour's suggestion: `HomeSuggestion` answers with a `Technique`, and
    /// everything that begins one takes a stop. Written here rather than at that
    /// call site because the band has to be the one `id(of:)` answers with —
    /// otherwise the suggestion's row would carry an id no star could ever
    /// match, and starring what Home just offered would pin a second row.
    ///
    /// - Parameter dialled: what this person dialled for the technique
    ///   themselves, or nil where they take it as curated.
    public static func standingFor(
        _ technique: Technique,
        dialled: TechniqueOverrides? = nil
    ) -> DialStop {
        DialStop(
            technique: technique,
            origin: .technique,
            band: technique.origin == .personal ? .yours : .everything,
            saved: dialled
        )
    }

    private static func id(in band: DialBand, key: String) -> ID {
        "\(band.rawValue)/\(key)"
    }

    /// The stop's name in its own band, before the band is prefixed.
    private var key: String {
        switch origin {
        case let .occasion(occasion): occasion.slug
        case .step, .technique: technique.slug
        }
    }

    /// The line in focus.
    public var title: String {
        switch origin {
        case let .occasion(occasion): occasion.name
        case .step, .technique: technique.name
        }
    }

    /// One sentence about this stop, or empty where nobody wrote one.
    ///
    /// Whichever of the three is the truthful sentence for the origin: an
    /// occasion's own words about the moment, a rung's note on why it sits where
    /// it does, or the exercise's summary. A rung whose note is empty falls back
    /// to that summary, which is exactly what `ProgressionStep.note` promises by
    /// documenting empty as "the technique's own summary is enough".
    public var summary: String {
        switch origin {
        case let .occasion(occasion): occasion.summary
        case let .step(step): step.note.isEmpty ? technique.summary : step.note
        case .technique: technique.summary
        }
    }

    /// The occasion this stop routes through, or nil for a rung or a plain
    /// technique — what a started session stamps onto its record, so the
    /// journey can tell a prescribed session from a chosen one.
    public var occasionSlug: String? {
        switch origin {
        case let .occasion(occasion): occasion.slug
        case .step, .technique: nil
        }
    }

    /// The caution this exact launch carries. A protocol's warning takes
    /// precedence because it describes doing the exercise in that context;
    /// otherwise the exercise's own warning remains in force.
    public var warning: SessionWarning? {
        switch origin {
        case let .occasion(occasion):
            if let note = occasion.prescription.safetyNote {
                return SessionWarning(
                    key: "occasion/\(occasion.slug)",
                    title: occasion.name,
                    text: note
                )
            }
            return technique.sessionWarning
        case .step, .technique:
            return technique.sessionWarning
        }
    }

    /// The goal this stop is framed as, and therefore the accent it wears. An
    /// occasion borrows one rather than reading the technique's, because what a
    /// moment is for must not move because a technique was re-grouped.
    public var goal: TechniqueGoal {
        switch origin {
        case let .occasion(occasion): occasion.prescription.goal
        case .step, .technique: technique.goal
        }
    }

    /// How loudly this stop runs. Everything outside an occasion is full
    /// screen: the catalogue makes no promise about quietness, and inventing
    /// one here would be this app guessing at a route the server never sent.
    public var surface: DeliverySurface {
        switch origin {
        case let .occasion(occasion): occasion.prescription.surface
        case .step, .technique: .fullScreen
        }
    }

    /// The two facts every row states about this stop — "relax · 5 min".
    ///
    /// Here rather than in a view because more than one draws it: Home's starred
    /// rows and the Protocols list both print it under the name, and written
    /// twice the separator, the order or the length's format is free to drift
    /// between two rows for the same exercise on one screen.
    public var basics: String {
        "\(goal.intentObject) · \(duration.glanceable)"
    }

    /// The same, with the marks about what tapping will actually do — "· Plus"
    /// where it opens the paywall, "· on your watch" where only the wrist can
    /// deliver it quietly.
    ///
    /// A row draws those marks as glyphs where it draws them at all, and a glyph
    /// is nothing VoiceOver reads. Every row speaks this, so a locked exercise
    /// says so before the tap rather than only where the caption has room. Built
    /// off `basics` so the spoken sentence and the printed one open the same way.
    ///
    /// - Parameter tier: what this person is entitled to. It decides only
    ///   whether the Plus mark is *stated*; what the lock gates is
    ///   `Technique.isUnlocked(for:)`'s to answer and nothing here changes it.
    public func facts(for tier: SubscriptionTier) -> String {
        let plus = technique.isUnlocked(for: tier) ? "" : " · Plus"
        let wrist = surface == .discreet ? " · on your watch" : ""
        return "\(basics)\(plus)\(wrist)"
    }

    /// The whole of what VoiceOver hears before a row is tapped: what this is,
    /// and what tapping it will do.
    ///
    /// Here rather than on either row because a label set on a button *replaces*
    /// every label composed underneath it — the goal, the length, and the lock
    /// and watch marks that were unreadable as glyphs to begin with. So the
    /// sentence has to be written out, and written once: Home's shelf and the
    /// Protocols list reading differently for one exercise is the same defect as
    /// one of them reading nothing. It also puts the claim where a test can pin
    /// it, which an app target has no bundle to do.
    public func spokenLabel(for tier: SubscriptionTier) -> String {
        "\(title), \(facts(for: tier))"
    }

    /// Which words this stop speaks, on `surface`'s reasoning: a register is
    /// something a route asks for, and a catalogue entry standing for itself has
    /// asked for nothing. Reaching the same exercise off the Exercises list
    /// therefore speaks plainly, which is the point rather than an oversight —
    /// the playful words belong to the moment somebody arrived through, not to
    /// the exercise.
    public var register: CopyRegister {
        switch origin {
        case let .occasion(occasion): occasion.prescription.register
        case .step, .technique: .plain
        }
    }
}
