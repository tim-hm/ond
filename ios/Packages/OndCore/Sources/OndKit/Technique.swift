import Foundation

public struct Phase: Sendable, Hashable, Codable {
    /// What the breath does here, and where the air goes with it.
    public let breath: Breath
    /// The curated default, and what a session plays unless a dial moved it.
    public private(set) var duration: Duration
    /// The evidence-based range, inclusive. Seeded per phase, so the Customise
    /// dials render from the catalogue rather than from limits the app would
    /// have to keep in step with it; a single-point range means no dial at all.
    /// On a stage the person ends it doubles as the typical band the figure and
    /// steps print (`hold · 30s–2m`), and its dial sets the first round's aim.
    public private(set) var range: ClosedRange<Duration>
    /// How the breath is shaped, or nil — which is most phases.
    ///
    /// Seeded per phase on `range`'s reasoning: the app states no mechanic of its
    /// own, so a technique gains one by being reseeded rather than by this app
    /// learning a slug.
    public let manner: Manner?
    /// The stillness this phase's table authored to close it, or nil to let
    /// ``SessionTurnGap`` size one from the phase's own length. Nil for every
    /// seeded phase: a cadence is one authored deliverable per exercise, and
    /// none is written yet. An authored zero is not nil — it says this rhythm
    /// turns without a gap, which a continuous exercise means.
    public let turnGap: Duration?
    /// The tap this phase plays and the line it speaks, named by keys the
    /// client resolves. Nil on ``turnGap``'s terms and for its reason.
    public let hapticPattern: String?
    public let voiceScript: String?

    /// Defaults the range to the duration itself — the honest description of a
    /// phase nobody has widened, and what keeps a hand-built `Phase` in a test
    /// or a preview to one line. The manner and the cadence default to none for
    /// the same reason, and because both are the catalogue's exception.
    public init(
        _ breath: Breath,
        duration: Duration,
        range: ClosedRange<Duration>? = nil,
        manner: Manner? = nil,
        turnGap: Duration? = nil,
        hapticPattern: String? = nil,
        voiceScript: String? = nil
    ) {
        self.breath = breath
        self.duration = duration
        self.range = range ?? duration ... duration
        self.manner = manner
        self.turnGap = turnGap
        self.hapticPattern = hapticPattern
        self.voiceScript = voiceScript
    }

    /// The same phase said as a kind and a passage, for the two decoders that
    /// receive the pair separately and for hand-built test and preview phases.
    /// The passage defaults to the nose, which most seeded techniques use
    /// throughout; a hold ignores it, because `Breath` has nowhere to put one.
    public init(
        kind: PhaseKind,
        through passage: Passage = .nose,
        duration: Duration,
        range: ClosedRange<Duration>? = nil,
        manner: Manner? = nil
    ) {
        self.init(
            Breath(kind: kind, through: passage),
            duration: duration,
            range: range,
            manner: manner
        )
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
        carrying(duration: range.clamping(duration), range: range)
    }

    /// The same phase at another length, keeping everything the length does not
    /// decide. A copy rather than a rebuild through the initialiser, on
    /// `Technique.replacing`'s reasoning: a rebuild forgets each newly added
    /// field silently, and the curated copy was lost that way one type up.
    public func carrying(duration: Duration, range: ClosedRange<Duration>) -> Self {
        var copy = self
        copy.duration = duration
        copy.range = range
        return copy
    }
}

/// A run of cycles sharing one phase pattern.
///
/// The general case a plain cyclic technique degenerates to: box breathing is
/// one stage repeated to five minutes, while a Wim Hof-style round is four — fast
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

    /// Which phase of the pattern has the most room to be spoken into — where
    /// a line that teaches rather than instructs goes. The first of equals,
    /// and zero for an empty pattern, which the repository already refuses.
    var longestPhase: Int {
        phases.indices.max { phases[$0].duration < phases[$1].duration } ?? 0
    }

    /// Whether the stage outruns a second-by-second count: a phase under two
    /// seconds prints two digits before it ends, so the session screen drops
    /// the count. Whole-stage, because a per-phase count would flicker on the
    /// sigh's mixed rhythm. Not `breathesFast` — that is physiology at 4s a
    /// cycle, this legibility at 2s a phase; the sigh is true here, false there.
    public var isFastRhythm: Bool {
        phases.contains { $0.duration < Self.fastPhase }
    }

    /// The length a phase must stay under to outrun its own count. Under two
    /// seconds rather than at it: the catalogue floors several dials exactly at
    /// two, and an inclusive rule would let dragging one to its own floor strip
    /// the count off the four-second breath beside it.
    static let fastPhase = Duration.seconds(2)
}

/// One breathing exercise: what it is, how it is played, and what it costs.
/// The interface says "exercise"; the code keeps `Technique` because the name
/// runs through the proto, the `technique_slug` column, and the seed — a
/// rename would break the contract for nothing a person would notice.
/// `Hashable` for `NavigationStack` values; `Codable` for the offline cache.
public struct Technique: Sendable, Identifiable, Hashable, Codable {
    public let id: TechniqueId
    /// The stable key this app pins artwork and haptic patterns to.
    public let slug: TechniqueSlug
    public let name: String

    /// What it does and when to reach for it, in one sentence — a row's
    /// worth, which is where a curated one is read. For an exercise somebody
    /// wrote it is also the whole of what they had to say, and `closingNote`
    /// carries it onto the screen.
    public let summary: String

    /// Why it works, as complete plain text, or nil where nobody has written
    /// it; the exercise's own screen closes on it through `closingNote`. Nil
    /// rather than empty: the wire says "nothing here" with an empty string,
    /// and rendering one would draw a blank section. Always nil for a composed
    /// exercise — this app does not invite an author to assert physiology.
    public let mechanism: String?

    /// Scannable mechanism copy, falling back to `mechanism` for an older server.
    public let mechanismContent: ReadingContent?

    /// What the research actually shows, as complete plain text, or nil where
    /// nobody has written it. Kept apart from `mechanism` because one must not
    /// soften the other: the mechanism says how it is supposed to work, this
    /// says what the evidence is worth — including where it is thin. Nil, not
    /// empty, on `mechanism`'s terms; always nil for a composed exercise.
    public let evidence: String?

    /// The evidence verdict and findings, with `evidence` as the compatibility fallback.
    public let evidenceContent: ReadingContent?

    /// The verdict above in one word, or nil where nobody has graded this
    /// exercise. Nil is not a backlog — it is the permanent, honest answer for
    /// a composed exercise, on `evidence`'s terms. A row draws the chip only
    /// where there is a grade.
    public let evidenceGrade: EvidenceGrade?

    public let goal: TechniqueGoal

    /// The session, in play order. Never empty.
    public private(set) var stages: [Stage]
    /// The curated default number of times a session repeats the whole stage
    /// list. One for everything cyclic; a person's own preference overrides it
    /// for the session they are starting.
    public private(set) var recommendedRounds: Int
    /// The caution this technique carries, or nil where it carries none —
    /// curated copy for the two exercises that can make somebody faint. A note
    /// here stands a full-screen warning (`TechniqueWarningView`) between the
    /// phone's Begin and its countdown, accepted and silenced explicitly. The
    /// watch has no pre-start sequence to hang it on: a gap, not a decision.
    public let safetyNote: String?

    /// What to do with your body before the first breath, or nil where the
    /// exercise asks for nothing. It carries what [`Manner`] cannot: the
    /// alternative for somebody the shape does not fit — closed teeth for a
    /// tongue that will not roll. The phone renders it, the watch does not (a
    /// gap, not a decision); VoiceOver is unaffected via `BreathHint.spokenAddition`.
    public let preparation: String?

    /// Preparation as prose, bullets or ordered steps.
    public let preparationContent: ReadingContent?

    /// The tier this one needs. A tier rather than a boolean, so a gate is the
    /// same comparison everywhere and a future tier needs no new field.
    /// Defaulted to `.free`, mirroring the proto's zero value: a decode gap
    /// that locked something must never be the quiet outcome.
    public let requires: SubscriptionTier

    /// Where this one came from. Defaulted to `.catalogue`, which is what every
    /// hand-built `Technique` in a test or a preview means, and what the two
    /// decoding paths onto this type both produce.
    public let origin: TechniqueOrigin

    public init(
        id: TechniqueId,
        slug: TechniqueSlug,
        name: String,
        summary: String,
        goal: TechniqueGoal,
        stages: [Stage],
        recommendedRounds: Int,
        // Defaulted, like `safetyNote` and for the same reason: every hand-built
        // `Technique` in a test or a preview means "no curated paragraph".
        mechanism: String? = nil,
        mechanismContent: ReadingContent? = nil,
        evidence: String? = nil,
        evidenceContent: ReadingContent? = nil,
        evidenceGrade: EvidenceGrade? = nil,
        safetyNote: String? = nil,
        preparation: String? = nil,
        preparationContent: ReadingContent? = nil,
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
        self.mechanismContent = ReadingContent.resolved(mechanismContent, fallback: self.mechanism)
        self.evidence = evidence?.nilIfEmpty
        self.evidenceContent = ReadingContent.resolved(evidenceContent, fallback: self.evidence)
        self.evidenceGrade = evidenceGrade
        self.safetyNote = safetyNote?.nilIfEmpty
        self.preparation = preparation?.nilIfEmpty
        self.preparationContent = ReadingContent.resolved(
            preparationContent,
            fallback: self.preparation
        )
        self.requires = requires
        self.origin = origin
    }

    /// A copy with the two dialled fields replaced — the one authorised way to
    /// reshape a technique. Rebuilding against the initialiser, whose tail
    /// parameters all default, silently dropped each newly added field;
    /// `requires`, `origin` and `mechanism` were each lost that way. A copy
    /// cannot forget a field it never enumerates.
    public func replacing(stages: [Stage], recommendedRounds: Int) -> Technique {
        var copy = self
        copy.stages = stages
        copy.recommendedRounds = recommendedRounds
        return copy
    }

    /// Whether `tier` opens this technique. On the type because four surfaces
    /// ask it, and four copies of the comparison are four chances to write `>`
    /// where `>=` belongs.
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

    /// Whether this technique is one breath repeated — neither staged nor
    /// open-ended, with a cycle that takes time — and so can be asked to last
    /// a length by playing more or fewer cycles. Staged protocols and the
    /// breath-holds you end yourself are not: their length is their shape.
    public var isCyclic: Bool {
        !isStaged && !hasOpenEndedStage && (stages.first?.cycleDuration ?? .zero) > .zero
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
