import Foundation

/// How far a practice has come, earned only by practising. Not
/// `ExperienceLevel`, which is what somebody said about themselves once. The
/// ladder counts sessions, not minutes or breaths, so the only way to climb is
/// to come back. A session ended early counts; a false start is not practice.
/// Derived, never stored, so deleting the history deletes the stage with it.
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

    /// What the stage is called, wherever it stands rather than arrives. Every
    /// name describes the practice, never the person: "a habit forming", not
    /// "intermediate".
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

    /// What is said on the session that crosses into it, once. Warm, short and
    /// past tense. Nothing here names the rung above or how far off it is: a
    /// ladder that always shows the next rung always says "not yet".
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
    /// session. Nil rather than a zeroth rung, because somebody who has not
    /// started has not fallen short of anything.
    public static func held(atSessionCount count: Int) -> Self? {
        allCases.filter { count >= $0.sessionsNeeded }.max()
    }

    /// The rung a count crosses on its way from `previous` to `count`, or nil
    /// where it crosses none. A crossing rather than an exact landing, because
    /// `SessionRecording.merge` can carry a whole backlog in one call and a
    /// deletion takes rows away. A jump of several rungs answers with the
    /// highest. It remembers nothing, so a rung crossed by a merge is silent.
    public static func reached(movingFrom previous: Int, to count: Int) -> Self? {
        let now = held(atSessionCount: count)
        return now == held(atSessionCount: previous) ? nil : now
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionsNeeded < rhs.sessionsNeeded
    }
}
