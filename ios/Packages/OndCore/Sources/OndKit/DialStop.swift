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
    /// The named moments — `Routes.occasions`, in seeded order.
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
        /// A named moment, with the goal, surface and dose it prescribes.
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

    /// The dials this stop starts with, or nil where the technique is played
    /// exactly as the catalogue curated it.
    public let dose: TechniqueOverrides?

    /// The technique as this stop will actually play it — `technique` with `dose`
    /// applied.
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

        dose = switch origin {
        case let .occasion(occasion): occasion.prescription.dose(for: technique)
        case .step, .technique: saved
        }
        dialled = technique.dialled(with: dose)
        duration = dialled.plannedDuration
    }

    /// Unique across the whole dial, which the technique's slug is not: Start
    /// here names four of the catalogue's nine, so the same exercise is a stop
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
    /// answer "is this exercise on the board". Start here names four of the
    /// catalogue's nine, so somebody who starred Box Breathing from home starred
    /// `startHere/box-breathing` — and a toolbar comparing only against
    /// `everything/box-breathing` would draw an empty star over an exercise already
    /// pinned, then deal a second identical row when it was tapped.
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

    /// The occasion this stop routes through, or nil for a rung or a plain
    /// technique — what a started session stamps onto its record, so the
    /// journey can tell a prescribed session from a chosen one.
    public var occasionSlug: String? {
        switch origin {
        case let .occasion(occasion): occasion.slug
        case .step, .technique: nil
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
