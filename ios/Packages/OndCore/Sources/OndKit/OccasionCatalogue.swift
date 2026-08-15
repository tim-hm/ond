import Foundation

/// How loudly a session runs.
///
/// The load-bearing half of an occasion, and the reason occasions are more than
/// a second name for a goal: "through this meeting" and "after a hard meeting"
/// reach for the same technique at the same pace and differ only here.
///
/// The raw value is a stored key — routes are cached on disk beside the
/// catalogue — and a synthesised case name is not a key that should survive a
/// refactor.
public enum DeliverySurface: String, Sendable, Hashable, Codable {
    /// The session owns the screen: the figure, the counts, the haptics.
    case fullScreen

    /// The session runs where nobody watching would notice it — a wrist tapping
    /// out the rhythm, no animation, no sound. Today only `OndWatch` can
    /// deliver one, which is a fact every phone surface offering one has to
    /// say out loud rather than quietly start something else.
    case discreet
}

/// Who a session is speaking to, and therefore how it presents itself.
///
/// A property of the route, never of the technique, on `DeliverySurface`'s
/// terms: the same exercise is read plainly by an adult browsing the catalogue
/// and playfully by a parent who arrived through the moment that names a child.
///
/// **It is not only wording.** It began as the words and now also picks the
/// accent a session is grounded in (`CopyRegister.accent(over:)`) and which
/// guide is drawn — flower and candle rather than the sphere. Any surface
/// showing a session reads all three, so a new one that reaches for
/// `goal.accent` directly will disagree with the screen beside it. That is not
/// hypothetical: the Live Activity did exactly that for as long as this
/// paragraph said "which words".
///
/// What it deliberately does not touch: the rhythm, the dose, and the person's
/// own `BreathVisualStyle` and Reduce Motion settings. A register changes how a
/// session speaks, never what it asks somebody to breathe.
///
/// The raw value is a stored key, for `DeliverySurface`'s reason — routes are
/// cached on disk.
public enum CopyRegister: String, Sendable, Hashable, Codable, CaseIterable {
    /// "Breathe in", "Hold", "Breathe out" — what every route speaks unless it
    /// asks for otherwise.
    case plain

    /// The same phases named as a small child can follow them. Which breaths it
    /// covers is `Breath.playfulInstruction`'s to state.
    case playful
}

/// What an occasion resolves to: which technique, framed as what, run how, for
/// how long, with any rhythm or caution belonging to the protocol itself.
public struct Prescription: Sendable, Hashable, Codable {
    /// The technique to breathe, by the key the catalogue keeps stable. Nothing
    /// else about that technique is repeated here — a locked flag copied onto a
    /// route would be a second copy of a promise free to disagree with the
    /// first.
    public let techniqueSlug: String

    /// The goal this moment borrows, so the home screen and the coach keep
    /// speaking the five goals they already speak. Carried by the occasion
    /// rather than read back through the catalogue: what a moment is for should
    /// not move because a technique was re-grouped.
    public let goal: TechniqueGoal

    public let surface: DeliverySurface

    /// Which words the session speaks. Absent means the plain one — which is
    /// what every occasion seeded before the field existed says by saying
    /// nothing.
    public let register: CopyRegister

    /// A protocol-owned rhythm in the resolved exercise's phase order. Empty
    /// keeps the exercise's own phase durations.
    public let phaseDurations: [Duration]

    /// A caution belonging to this protocol rather than to every direct start
    /// of the exercise it uses.
    public let safetyNote: String?

    /// How long the occasion asks for — a target to fit whole cycles into, not
    /// a stopwatch to cut a breath short with. `dialled(_:)` turns it into a
    /// session.
    public let duration: Duration

    public init(
        techniqueSlug: String,
        goal: TechniqueGoal,
        surface: DeliverySurface,
        register: CopyRegister = .plain,
        duration: Duration,
        phaseDurations: [Duration] = [],
        safetyNote: String? = nil
    ) {
        self.techniqueSlug = techniqueSlug
        self.goal = goal
        self.surface = surface
        self.register = register
        self.duration = duration
        self.phaseDurations = phaseDurations
        self.safetyNote = safetyNote?.nilIfEmpty
    }

    /// Hand-written for one key: `register` is absent from every routes snapshot
    /// written before it existed, and a synthesised decoder treats a missing key
    /// as a failure however the memberwise init defaults it.
    ///
    /// `CachedReferenceRepository` restores routes from JSON on disk, so one
    /// unreadable key would drop the whole snapshot and leave home with no
    /// occasions offline until a background refresh repairs it. Every key a
    /// route gains from here needs the same treatment.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        techniqueSlug = try container.decode(String.self, forKey: .techniqueSlug)
        goal = try container.decode(TechniqueGoal.self, forKey: .goal)
        surface = try container.decode(DeliverySurface.self, forKey: .surface)
        register = try container.decodeIfPresent(CopyRegister.self, forKey: .register) ?? .plain
        duration = try container.decode(Duration.self, forKey: .duration)
        phaseDurations = try container.decodeIfPresent(
            [Duration].self,
            forKey: .phaseDurations
        ) ?? []
        safetyNote = try container.decodeIfPresent(String.self, forKey: .safetyNote)?.nilIfEmpty
    }
}

/// A named moment somebody might open the app in, and where it routes.
///
/// Occasions do not add exercises to the catalogue: each is a protocol over a
/// technique that is listed and described whether or not this entry exists.
public struct Occasion: Sendable, Hashable, Codable, Identifiable {
    /// Stable key ("before-a-presentation"), so a surface can pin an icon or an
    /// event to an occasion without pinning its wording.
    public let slug: String

    /// How the moment is named to the person, in their words rather than the
    /// catalogue's.
    public let name: String

    /// One sentence on what this does for them here, or empty.
    public let summary: String

    public let prescription: Prescription

    public var id: String {
        slug
    }

    public init(slug: String, name: String, summary: String, prescription: Prescription) {
        self.slug = slug
        self.name = name
        self.summary = summary
        self.prescription = prescription
    }
}

/// One rung of the Start here progression.
public struct ProgressionStep: Sendable, Hashable, Codable, Identifiable {
    public let techniqueSlug: String

    /// Why this one, at this point — the sentence that makes the order a
    /// progression rather than a list. Empty means the technique's own summary
    /// is enough.
    public let note: String

    public var id: String {
        techniqueSlug
    }

    public init(techniqueSlug: String, note: String) {
        self.techniqueSlug = techniqueSlug
        self.note = note
    }
}

/// The routing layer over the catalogue: named moments, and the order somebody
/// with no goal at all should meet the exercises in.
///
/// One value rather than two loads because they answer one question — where
/// somebody who has not chosen begins — and a screen holding the occasions
/// without the progression would render half of itself.
///
/// The progression gates nothing. It names a few of the techniques the
/// catalogue serves and changes nothing about the rest: none is hidden or
/// reordered by its absence, and reaching a step is never a condition of
/// breathing the one after it.
public struct OccasionCatalogue: Sendable, Hashable, Codable {
    /// Ordered for display, in the order somebody is most likely to want them.
    public let occasions: [Occasion]

    /// The Start here progression, in curated order.
    public let progression: [ProgressionStep]

    public init(occasions: [Occasion] = [], progression: [ProgressionStep] = []) {
        self.occasions = occasions
        self.progression = progression
    }

    /// Nothing to route by.
    ///
    /// Rarer than it was — this build ships a bundled routing layer, so a first
    /// launch out of range answers with the seeded moments rather than with
    /// this. What still reaches it is a build whose export could not be read,
    /// and a model that has not loaded yet. Every reader stays written to work
    /// against it: an occasion list is a layer *over* the catalogue, so having
    /// none of them costs a way in rather than the exercise.
    public static let none = OccasionCatalogue()
}

public extension Prescription {
    /// The resolved exercise exactly as this protocol asks it to play.
    ///
    /// Protocol rhythms are curated session facts, not a person's exercise
    /// customization. Their ranges are widened only on this transient copy so
    /// a deliberate protocol duration outside the standalone dial's limits is
    /// preserved without weakening those limits everywhere else. A cyclic
    /// exercise then fits whole breaths near the requested duration; staged and
    /// open-ended exercises keep their curated length.
    func dialled(_ technique: Technique) -> Technique {
        var prescribed = technique
        let hasPositivePhaseDurations = phaseDurations.allSatisfy { $0 > .zero }
        if let stage = technique.stages.first {
            let replacesRhythm = !phaseDurations.isEmpty
                && technique.stages.count == 1
                && !stage.openEnded
                && phaseDurations.count == stage.phases.count
                && hasPositivePhaseDurations
            if replacesRhythm {
                let phases = zip(stage.phases, phaseDurations).map { phase, duration in
                    Phase(
                        phase.breath,
                        duration: duration,
                        range: min(phase.range.lowerBound, duration) ... max(
                            phase.range.upperBound,
                            duration
                        )
                    )
                }
                prescribed = technique.replacing(
                    stages: [Stage(phases: phases, cycles: stage.cycles)],
                    recommendedRounds: 1
                )
            }
        }

        guard prescribed.stages.count == 1,
              let stage = prescribed.stages.first,
              !stage.openEnded,
              stage.cycleDuration > .zero
        else {
            return prescribed
        }

        let wanted = Double(duration.milliseconds) / Double(stage.cycleDuration.milliseconds)
        var overrides = prescribed.curatedOverrides
        overrides.stages[0].cycles = TechniqueOverrides.cycleRange.clamping(
            Int(wanted.rounded())
        )
        overrides.rounds = 1
        return prescribed.dialled(with: overrides)
    }
}
