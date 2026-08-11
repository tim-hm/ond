import Foundation

/// The outcome a technique is chosen for.
///
/// Distinct from the generated `Ond_V1_TechniqueGoal` on purpose: that type
/// carries an `UNSPECIFIED` case the wire format can always produce, and every
/// view that switched over it would need a branch for a value that means
/// "the server and this app disagree". Decoding resolves that once, here.
///
/// The raw value exists so a goal can be written down: the answers someone gives
/// at onboarding are stored locally as JSON, and a synthesised case name is not
/// a key that should survive a refactor.
public enum TechniqueGoal: String, Sendable, CaseIterable, Codable {
    case calm
    case sleep
    case energy
    case reset
    case focus
}

/// One segment of a breathing cycle.
///
/// The raw value is a stored key — the catalogue is cached on disk so the app
/// can breathe offline — and a synthesised case name is not a key that should
/// survive a refactor.
public enum PhaseKind: String, Sendable, Hashable, Codable {
    case inhale
    case holdIn
    case exhale
    case holdOut
}

/// Who wrote a technique, and therefore who may change it.
///
/// Not carried on the wire: a technique's origin is which service answered for
/// it, and `UserTechniqueRepository` is the only thing that ever stamps
/// `.personal`. It lives on the domain type so that everything above the
/// repositories — a list section, a detail screen deciding between Customise and
/// Edit — asks one question instead of tracking which array a value came out of.
public enum TechniqueOrigin: String, Sendable, Hashable, Codable {
    /// Curated, seeded, and the same for everybody.
    case catalogue

    /// Composed by the person holding the phone, and stored server-side against
    /// their identity so it is the same exercise on every device they use.
    case personal
}

/// What the breath does in one phase, and — where air is moving — where it goes.
///
/// The passage rides on the movement rather than sitting beside it, so a hold
/// through the left nostril cannot be written down: air that is not moving goes
/// nowhere, and the two hold cases have no passage to carry. That is the same
/// shape `ond.v1.DraftPhase`'s oneof has, for the same reason — and it makes
/// decoding a served `Phase` total rather than a silent drop of a field that
/// should never have been set.
///
/// Four cases mirroring `PhaseKind` rather than three with a lungs state,
/// because `kind` is what every cue, haptic and colour switches on and a second
/// vocabulary for the same distinction would be one more thing to keep in step.
public enum Breath: Sendable, Hashable, Codable {
    case inhale(through: Passage)
    case holdIn
    case exhale(through: Passage)
    case holdOut

    public var kind: PhaseKind {
        switch self {
        case .inhale: .inhale
        case .holdIn: .holdIn
        case .exhale: .exhale
        case .holdOut: .holdOut
        }
    }

    /// Where the air goes, or nil for a hold.
    public var passage: Passage? {
        switch self {
        case let .inhale(passage), let .exhale(passage): passage
        case .holdIn, .holdOut: nil
        }
    }

    /// The breath a `kind` and a passage describe, with the passage consulted
    /// only where there is somewhere to put it.
    ///
    /// The one way onto this type from the pair the wire and the database carry
    /// separately. Total in both arguments: a hold arriving with a passage
    /// resolves to a hold, because the case it maps to has no room for one.
    public init(kind: PhaseKind, through passage: Passage) {
        switch kind {
        case .inhale: self = .inhale(through: passage)
        case .holdIn: self = .holdIn
        case .exhale: self = .exhale(through: passage)
        case .holdOut: self = .holdOut
        }
    }
}

/// Written out rather than synthesised, because the associated passage stops
/// the compiler doing it.
///
/// Worth having as a list at all because this type is a vocabulary as much as a
/// model: it is the set of things the app can say, so the tests that ask whether
/// everything sayable has been said need to enumerate it.
extension Breath: CaseIterable {
    public static var allCases: [Breath] {
        Passage.allCases.flatMap { [Breath.inhale(through: $0), .exhale(through: $0)] }
            + [.holdIn, .holdOut]
    }
}

public struct Phase: Sendable, Hashable, Codable {
    /// What the breath does here, and where the air goes with it.
    public let breath: Breath
    /// The curated default, and what a session plays unless a dial moved it.
    public let duration: Duration
    /// The evidence-based range, inclusive. Seeded per phase, so the Customise
    /// dials render from the catalogue rather than from limits the app would
    /// have to keep in step with it; a single-point range means no dial at all.
    /// On a stage the person ends it doubles as the typical band the figure and
    /// steps print (`hold · 30s–2m`), and its dial sets the first round's aim.
    public let range: ClosedRange<Duration>

    /// Defaults the range to the duration itself — the honest description of a
    /// phase nobody has widened, and what keeps a hand-built `Phase` in a test
    /// or a preview to one line.
    public init(_ breath: Breath, duration: Duration, range: ClosedRange<Duration>? = nil) {
        self.breath = breath
        self.duration = duration
        self.range = range ?? duration ... duration
    }

    /// The same phase said as a kind and a passage, for the two decoders that
    /// receive the pair separately and for the hand-built phases of tests and
    /// previews.
    ///
    /// The passage defaults to the nose, which is what eight of the ten seeded
    /// techniques do throughout and what the foundations teach — and a hold
    /// ignores it, because `Breath` has nowhere to put one.
    public init(
        kind: PhaseKind,
        through passage: Passage = .nose,
        duration: Duration,
        range: ClosedRange<Duration>? = nil
    ) {
        self.init(Breath(kind: kind, through: passage), duration: duration, range: range)
    }

    public var kind: PhaseKind {
        breath.kind
    }

    /// Where the air goes, or nil for a hold.
    public var passage: Passage? {
        breath.passage
    }

    /// Whether there is anything to drag — a range wider than a single point.
    public var isAdjustable: Bool {
        range.lowerBound < range.upperBound
    }

    /// The same phase at `duration`, clamped into its own range — a dial cannot
    /// take a phase somewhere the catalogue says it should not go.
    public func dialled(to duration: Duration) -> Self {
        Self(breath, duration: range.clamping(duration), range: range)
    }
}

/// A run of cycles sharing one phase pattern.
///
/// The general case a plain cyclic technique degenerates to: box breathing is
/// one stage of eight cycles, while a Wim Hof-style round is four — fast
/// breaths, one deep breath, a retention the person ends, then a recovery hold.
public struct Stage: Sendable, Hashable, Codable {
    /// The pattern, in play order. Never empty — `TechniqueRepository` rejects
    /// an empty stage rather than handing a view a loop with nothing in it.
    public let phases: [Phase]
    public let cycles: Int
    /// Whether the person, rather than the clock, decides when this stage ends.
    ///
    /// True only for a retention hold. The session clock stops for one: its
    /// phase durations describe a typical hold, not a scheduled one, so nothing
    /// downstream may treat them as a length.
    public let openEnded: Bool

    public init(phases: [Phase], cycles: Int, openEnded: Bool = false) {
        self.phases = phases
        self.cycles = cycles
        self.openEnded = openEnded
    }

    /// How long one repetition of the pattern takes.
    public var cycleDuration: Duration {
        phases.totalDuration
    }

    /// How long the whole stage takes — nominal for an open-ended one, which is
    /// as good an estimate as exists before the person decides.
    public var duration: Duration {
        cycleDuration * max(cycles, 1)
    }

    /// Whether this stage moves faster than a second-by-second count can be read
    /// — bellows breathing, a Wim Hof round's power breaths, the sigh's two sips.
    ///
    /// A phase under two seconds prints two different digits before it is over,
    /// and a number changing that fast beside the orb is something to watch
    /// rather than a measure of anything. The session screen drops the count for
    /// these; somebody who wants the figures has them on the exercise's own page,
    /// where they hold still.
    ///
    /// Asked of the whole stage rather than of each phase, because a stage is one
    /// rhythm and the sigh's is 1.5s · 0.7s · 5s: per phase, the count would
    /// appear for the exhale and vanish for the sips, three times a cycle, which
    /// is more distracting than leaving it up. A Wim Hof round is the case this
    /// buys — its power breaths lose the count and its recovery keeps it, and the
    /// retention between them already replaces the screen.
    public var isFastRhythm: Bool {
        phases.contains { $0.duration < Self.fastPhase }
    }

    /// The length a phase has to stay under to outrun its own count.
    ///
    /// Under two seconds rather than at it, because two is exactly where the
    /// catalogue floors several dials — box breathing's holds, every breath in
    /// the Wim Hof recovery. Inclusive, dragging one of those to the bottom of
    /// its own curated range would strip the count off the four-second breath
    /// beside it, which is this rule inverted.
    private static let fastPhase = Duration.seconds(2)
}

/// One breathing exercise: what it is, how it is played, and what it costs.
///
/// The interface calls these **exercises** and the code calls them
/// **techniques**, on purpose. "Breathing exercise" is the phrase a general
/// audience already uses, so that is what every screen says; the domain keeps
/// `Technique` because the name runs through the proto contract, the
/// `technique_slug` column in `sessions`, the `technique_goal` Postgres enum,
/// and the seeded catalogue. Renaming the type would be a breaking proto change
/// and a column rename across server, watch and seed data, in exchange for
/// nothing a person using the app would notice. Read "technique" here as the
/// domain word for the thing the interface calls an exercise.
///
/// `Hashable` so a list row can push one as a `NavigationStack` value rather
/// than pushing a pre-built destination view. `Codable` because the last
/// fetched catalogue is kept on disk — the app breathes offline from it.
public struct Technique: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    /// The stable key this app pins artwork and haptic patterns to.
    public let slug: String
    public let name: String

    /// What it does and when to reach for it, in a sentence or two — a row's
    /// worth, which is where a curated one is read. For an exercise somebody
    /// wrote it is also the whole of what they had to say, and `closingNote`
    /// carries it onto the screen.
    public let summary: String

    /// Why it works, in a paragraph, or nil where nobody has written one.
    ///
    /// The exercise's own screen closes on this, through `closingNote`. Beside
    /// `summary` rather than a longer version of it, because the two are read in
    /// different places: a list of nine cannot carry nine paragraphs, and a
    /// caption on a row is not an explanation at the foot of a page.
    ///
    /// Nil rather than empty, on `safetyNote`'s terms — the wire and the export
    /// both say "nothing here" with an empty string, and a screen that rendered
    /// one would draw a blank paragraph. Always nil for an exercise somebody
    /// composed: the mechanism is curated reference copy, and inviting an author
    /// to assert physiology is not something this app should do.
    public let mechanism: String?

    public let goal: TechniqueGoal

    /// The session, in play order. Never empty.
    public private(set) var stages: [Stage]
    /// The curated default number of times a session repeats the whole stage
    /// list. One for everything cyclic; a person's own preference overrides it
    /// for the session they are starting.
    public private(set) var recommendedRounds: Int
    /// The caution this technique carries, or nil where it carries none.
    ///
    /// Curated copy for the two exercises that can make somebody faint, and the
    /// deliberate opposite of the per-technique notices that once sat on every
    /// screen: instead of a line under the breath guide, a note here stands a
    /// full-screen warning (`TechniqueWarningView`) between the phone's Begin
    /// and its countdown, accepted explicitly and silenceable explicitly
    /// (`TechniqueWarningStore`). The watch does not gate its own starts yet:
    /// its session screen has no pre-start sequence to hang a warning on, and
    /// it never shows onboarding's consent step either — a wrist-first start
    /// of these two meets nothing. A gap to close, not a decision.
    public let safetyNote: String?

    /// The tier this one needs. `.free` for the two the app opens with,
    /// `.plus` for the rest.
    ///
    /// A tier rather than a boolean so a gate is the same comparison everywhere
    /// — and so a future technique behind Coach needs no new field. Defaulted to
    /// `.free` in the initialiser, which mirrors the proto's zero value and
    /// keeps every hand-built `Technique` in a test or a preview to the lines it
    /// already had: a decode gap that locked something must never be the quiet
    /// outcome.
    public let requires: SubscriptionTier

    /// Where this one came from. Defaulted to `.catalogue`, which is what every
    /// hand-built `Technique` in a test or a preview means, and what the two
    /// decoding paths onto this type both produce.
    public let origin: TechniqueOrigin

    public init(
        id: String,
        slug: String,
        name: String,
        summary: String,
        goal: TechniqueGoal,
        stages: [Stage],
        recommendedRounds: Int,
        // Defaulted, like `safetyNote` and for the same reason: every hand-built
        // `Technique` in a test or a preview means "no curated paragraph".
        mechanism: String? = nil,
        safetyNote: String? = nil,
        requires: SubscriptionTier = .free,
        origin: TechniqueOrigin = .catalogue
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.summary = summary
        self.goal = goal
        self.stages = stages
        self.recommendedRounds = recommendedRounds
        // Empty is the wire's "nothing written"; collapsed once here so no
        // decoder or view has to ask.
        self.mechanism = mechanism?.nilIfEmpty
        self.safetyNote = safetyNote?.nilIfEmpty
        self.requires = requires
        self.origin = origin
    }

    /// A copy with the two dialled fields replaced and everything else kept —
    /// the one authorised way to reshape a technique.
    ///
    /// `dialled(with:)` used to rebuild the whole value against the initialiser
    /// above, whose tail parameters all default — so every field added to this
    /// type was a silent drop at that one site; `requires`, `origin` and
    /// `mechanism` were each lost that way. A copy cannot forget a field it
    /// never enumerates, and a named mutator over `private(set)` properties
    /// keeps the rest of the module from reshaping a technique in place.
    public func replacing(stages: [Stage], recommendedRounds: Int) -> Technique {
        var copy = self
        copy.stages = stages
        copy.recommendedRounds = recommendedRounds
        return copy
    }

    /// Whether `tier` opens this technique.
    ///
    /// On the type rather than at each call site, because "can this person
    /// breathe this" is asked from the list, the detail screen, home's dial,
    /// and the watch — and four copies of a comparison is four chances to write
    /// `>` where `>=` belongs.
    public func isUnlocked(for tier: SubscriptionTier) -> Bool {
        tier >= requires
    }

    /// Whether any stage waits on the person rather than the clock — which is
    /// what makes this technique's length an estimate rather than a promise.
    public var hasOpenEndedStage: Bool {
        stages.contains(where: \.openEnded)
    }

    /// Whether this is a staged protocol rather than one cycle repeated.
    ///
    /// The distinction the interface turns on: a staged technique is dialled in
    /// rounds and described stage by stage, a cyclic one in cycles.
    public var isStaged: Bool {
        stages.count > 1
    }

    /// How long a session takes at these settings.
    ///
    /// An open-ended stage counts at the typical hold it is seeded with, so this
    /// is an estimate for any technique that has one — the same number
    /// `SessionTimeline` lays out, without laying out every beat to find it.
    public var plannedDuration: Duration {
        stages.reduce(.zero) { $0 + $1.duration } * max(recommendedRounds, 1)
    }
}

extension [Phase] {
    /// How long the sequence takes end to end.
    ///
    /// One definition, so a technique's advertised cycle length and the length
    /// `SessionTimeline` actually lays out cannot drift apart.
    var totalDuration: Duration {
        reduce(.zero) { $0 + $1.duration }
    }
}
