import Foundation

/// The kinds of thing the dial holds, in the order it ticks through them. A
/// band is a promise about what a stop *is*; the recommendation is one of
/// them moved to the front — a position, not a zone. The case order is tick
/// order, not any surface's reading order: a screen that wants Start here
/// before the occasions says so itself.
public enum DialBand: String, Sendable, Hashable, CaseIterable {
    /// The named moments — `OccasionCatalogue.occasions`, in seeded order.
    case occasions

    /// The curated ordering for somebody who has picked no goal at all.
    case startHere

    /// What this person composed themselves, in the order the server keeps
    /// them. Its own band rather than folded into `everything`: "an exercise
    /// you wrote" is a different promise from "an exercise this app ships",
    /// and it is the one band whose stops nobody but its author can see.
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

    /// The technique as this stop will actually play it. Kept rather than
    /// rebuilt on every layout pass: two resolutions of one stop could
    /// disagree — the length printed on a card from one, the rhythm drawn
    /// beside it from the other.
    public let dialled: Technique

    /// How long this stop actually takes — read off the dialled technique
    /// rather than off the prescription, because an occasion asking for five
    /// minutes of something four minutes long gets four.
    public let duration: Duration

    /// Stored rather than computed, because layouts draw on every pass and
    /// `dialled(with:)` rebuilds a whole technique to answer.
    /// - Parameter saved: what this person dialled themselves, or nil for
    ///   curated. An occasion's prescription overrules it; everywhere else it
    ///   wins, and it must reach here — the row states a length the button owes.
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
    /// exists — the composer and the exercise screen both star without a stop.
    /// Written here, through the same formatter as `id`, because the strings
    /// must be equal or a star silently pins nothing. Deliberately not an
    /// occasion's or rung's id: a star is about the exercise, not the moment.
    public static func id(of technique: Technique) -> ID {
        id(in: technique.origin == .personal ? .yours : .everything, key: technique.slug.rawValue)
    }

    /// Every id a card standing for this exercise could carry, `id(of:)` among
    /// them — what a star control must compare against, because an install can
    /// still hold a persisted `startHere/...` star. Deliberately not the
    /// occasions: starring the moment is not starring the exercise, and
    /// clearing one by pressing the other would take away the wrong thing.
    public static func ids(standingFor technique: Technique) -> Set<ID> {
        [
            id(in: .yours, key: technique.slug.rawValue),
            id(in: .startHere, key: technique.slug.rawValue),
            id(in: .everything, key: technique.slug.rawValue),
        ]
    }

    /// Whether `ids` — a star set — holds any id standing for this exercise.
    ///
    /// The one question every star control and Home's offer ask, written once
    /// so that a retired band is retired everywhere at the same time.
    public static func isStarred(_ technique: Technique, among ids: Set<ID>) -> Bool {
        !ids.isDisjoint(with: Self.ids(standingFor: technique))
    }

    /// This exercise as a stop standing for itself — the one way to build a
    /// stop from outside this module. Written here because the band must be
    /// the one `id(of:)` answers with; otherwise the offer's row would carry
    /// an id no star could match, and starring it would pin a second row.
    /// - Parameter dialled: this person's own dialling, or nil for curated.
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
        case let .occasion(occasion): occasion.slug.rawValue
        case .step, .technique: technique.slug.rawValue
        }
    }

    /// The line in focus.
    public var title: String {
        switch origin {
        case let .occasion(occasion): occasion.name
        case .step, .technique: technique.name
        }
    }

    /// One sentence about this stop, or empty where nobody wrote one: an
    /// occasion's own words, a rung's note, or the exercise's summary. A rung
    /// whose note is empty falls back to the summary, exactly as
    /// `ProgressionStep.note` promises.
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
    public var occasionSlug: OccasionSlug? {
        switch origin {
        case let .occasion(occasion): occasion.slug
        case .step, .technique: nil
        }
    }

    /// The caution this exact launch carries. A moment's warning takes
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

    /// The two facts every row states about this stop — "relax · 5 min". Here
    /// rather than in a view because ``spokenLabel(for:)`` reads it; written
    /// twice, the format could drift between the row and what VoiceOver hears.
    /// The Moments list states ``mechanics(for:)`` instead.
    public var basics: String {
        "\(goal.intentObject) · \(duration.glanceable)"
    }

    /// The same, with the marks about what tapping will do — "· Plus", "· on
    /// your watch". A row draws those as glyphs, which VoiceOver cannot read,
    /// so every row speaks this and a locked exercise says so before the tap.
    /// - Parameter tier: decides only whether the Plus mark is *stated*; the
    ///   lock itself is `Technique.isUnlocked(for:)`'s to answer.
    public func facts(for tier: SubscriptionTier) -> String {
        "\(basics)\(marks(for: tier))"
    }

    /// The mechanics under a moment card's title — "Box Breathing · 3 min",
    /// with the same tap marks `facts(for:)` carries. The exercise is news on
    /// a card titled by the moment. The playful register is named where a
    /// route asks for it and the plain one never is: plain is the default
    /// voice, and a word on every card distinguishes nothing.
    public func mechanics(for tier: SubscriptionTier) -> String {
        let play = register == .playful ? " · playful" : ""
        return "\(technique.name) · \(duration.glanceable)\(play)\(marks(for: tier))"
    }

    /// The marks about what tapping will actually do — "· Plus" where it opens
    /// the paywall, "· on your watch" where only the wrist can deliver it
    /// quietly — stated once so the two captions that carry them cannot
    /// disagree about order or wording.
    private func marks(for tier: SubscriptionTier) -> String {
        let plus = technique.isUnlocked(for: tier) ? "" : " · Plus"
        let wrist = surface == .discreet ? " · on your watch" : ""
        return "\(plus)\(wrist)"
    }

    /// The whole of what VoiceOver hears before a row is tapped. Here because
    /// a label set on a button *replaces* every label composed underneath it,
    /// so the sentence must be written out — and once, where a test can pin
    /// it: Home's button and the Moments list reading differently for one
    /// exercise is the same defect as one of them reading nothing.
    public func spokenLabel(for tier: SubscriptionTier) -> String {
        "\(title), \(facts(for: tier))"
    }

    /// Which words this stop speaks, on `surface`'s reasoning: a register is
    /// something a route asks for, and a catalogue entry standing for itself
    /// has asked for nothing. The same exercise off the Exercises list speaks
    /// plainly on purpose — the playful words belong to the moment.
    public var register: CopyRegister {
        switch origin {
        case let .occasion(occasion): occasion.prescription.register
        case .step, .technique: .plain
        }
    }
}
