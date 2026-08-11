import Foundation

/// How far a practice has come, earned only by practising.
///
/// Not to be confused with `ExperienceLevel`, which is next to it in this
/// package and answers a different question. Experience is what somebody said
/// about themselves once, in onboarding, and nothing but their own hand ever
/// changes it. A stage is what they have actually done, and nothing but
/// sessions ever changes it.
///
/// The ladder counts sessions rather than minutes or breaths, and that choice is
/// the product's copy rule expressed as arithmetic. Minutes and breaths both
/// reward breathing harder or longer than somebody meant to; a session counts
/// once however long it ran, so the only way to climb is to come back. Showing
/// up is the whole of what is measured, which is what "celebrate consistency,
/// never pressure" has to mean once it becomes a number.
///
/// A session ended early counts, exactly as it counts everywhere else in the
/// app — see `SessionSummaryView` and `SessionRecord.minimumRecordedDuration`,
/// which already draw the only line the app draws: a false start is not
/// practice, and everything else is.
///
/// Derived, never stored, like every other number the journey shows
/// (`JourneyStats`) and like the server's own stance that everything is derived
/// on read. That also decides what happens when somebody deletes their history:
/// the stage it earned goes with it. Correct, and deliberately so — deletion is
/// deletion, and a rung that outlived the sessions that earned it would be a
/// residue of the data we were asked to forget.
public enum PracticeStage: Int, Sendable, CaseIterable, Comparable {
    case firstBreaths = 1
    case findingTheRhythm = 5
    case habitForming = 15
    case aPractice = 30
    case partOfTheDay = 60
    case wellPractised = 120
    case secondNature = 250

    /// How many sessions this stage asks for — which is the case's own raw
    /// value, so a rung and its threshold cannot drift apart.
    public var sessionsNeeded: Int {
        rawValue
    }

    /// What the stage is called, wherever it stands rather than arrives.
    ///
    /// Every name describes the practice, never the person: "a habit forming",
    /// not "intermediate". A ladder that ranks people has to have a bottom rung
    /// that means "bad at this", and there is no wording of that which survives
    /// the copy rule.
    public var title: String {
        switch self {
        case .firstBreaths: "First breaths"
        case .findingTheRhythm: "Finding the rhythm"
        case .habitForming: "A habit forming"
        case .aPractice: "A practice"
        case .partOfTheDay: "Part of the day"
        case .wellPractised: "Well practised"
        case .secondNature: "Second nature"
        }
    }

    /// What is said on the session that crosses into it — once, and then not
    /// again unless the sessions that earned it are deleted and the rung is
    /// genuinely re-earned.
    ///
    /// Warm, short, and past tense: it reports something that has happened
    /// rather than setting up what should happen next. Nothing here names the
    /// rung above or how far off it is — a ladder that always shows the next
    /// rung is a ladder that always says "not yet".
    public var arrival: String {
        switch self {
        case .firstBreaths: "Your first session. That's the hardest one done."
        case .findingTheRhythm: "Five sessions in — you're finding the rhythm."
        case .habitForming: "Fifteen sessions. Something is taking hold."
        case .aPractice: "Thirty sessions. This is a practice now."
        case .partOfTheDay: "Sixty sessions — this is part of your day."
        case .wellPractised: "A hundred and twenty sessions in. Well practised."
        case .secondNature: "Two hundred and fifty. Second nature."
        }
    }

    /// The stage a practice of this size stands at, or nil before the first
    /// session.
    ///
    /// Nil rather than a zeroth rung, because there is no honest name for one.
    /// Somebody who has not started has not fallen short of anything, and a
    /// screen that told them where they rank before they have breathed once is
    /// the app grading them for turning up.
    public static func held(atSessionCount count: Int) -> Self? {
        allCases.filter { count >= $0.sessionsNeeded }.max()
    }

    /// The rung a count crosses into on its way from `previous` to `count`, or
    /// nil where it crosses none — which is almost every session, and is the
    /// point: the ladder speaks once per rung and is quiet in between.
    ///
    /// A crossing rather than an exact landing, because the count is not only
    /// moved by sessions finishing one at a time. A restore merges a whole
    /// backlog in one call (`SessionRecording.merge`) and a deletion takes rows
    /// away again, so a rule that asked "is the count exactly a threshold"
    /// would be answering a question the caller cannot promise. A jump of
    /// several rungs answers with the highest reached rather than each in turn,
    /// which is the kinder reading: the ones underneath were passed, not
    /// missed.
    ///
    /// What this deliberately does **not** do is remember. A merge that carries
    /// somebody past a rung says nothing — there is no session to say it about
    /// — and no later session says it for them, because by then the rung is
    /// already held. That rung is not lost, it is simply shown rather than
    /// announced: `JourneyStats.stage` has it, on the screen built for it.
    /// Remembering instead would mean storing which rungs had been spoken, and
    /// a stored ladder is the thing this type's own note refuses to keep.
    public static func reached(movingFrom previous: Int, to count: Int) -> Self? {
        let now = held(atSessionCount: count)
        return now == held(atSessionCount: previous) ? nil : now
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionsNeeded < rhs.sessionsNeeded
    }
}
