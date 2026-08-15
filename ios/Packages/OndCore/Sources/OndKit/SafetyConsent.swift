import Foundation

/// The safety terms somebody agrees to once, before their first session.
///
/// One screen replaced a caution on every exercise, so this text has to carry
/// the union of what those cautions said — fainting, water, driving, and
/// stopping at the first sign of lightheadedness — without becoming a wall
/// nobody reads. Hence five short points rather than prose: the hazards are
/// unrelated to each other, and a paragraph that runs them together is read as
/// one thing and remembered as none.
///
/// A value rather than a pile of string literals in a view, because the words
/// have to be two things at once: what a screen renders, and what a person's
/// recorded consent says they agreed to. `text` is the join, and the record
/// keeps a copy of it.
public struct SafetyConsent: Sendable, Equatable {
    /// Bumped when the terms change in a way that makes an earlier agreement no
    /// longer an agreement to *these* words — a hazard added, a hazard dropped,
    /// a limit loosened. Deliberately not bumped for a typo or a rephrasing:
    /// that would put a full-screen wall in front of everybody who has the app,
    /// which teaches people to dismiss it. The recorded `text` is what proves
    /// the exact wording somebody saw; this number decides only who gets asked
    /// again.
    public let version: Int
    public let title: String
    public let intro: String
    /// The hazards, one to a line, in the order they are shown.
    public let points: [String]
    /// What the button says. Part of the terms rather than the view's business:
    /// a record of consent is a record of what the person was told they were
    /// doing by pressing it.
    public let agreement: String

    public init(version: Int, title: String, intro: String, points: [String], agreement: String) {
        self.version = version
        self.title = title
        self.intro = intro
        self.points = points
        self.agreement = agreement
    }

    /// Every word on the screen, in the order it appears, as one string.
    ///
    /// Composed rather than stored so the record and the rendering cannot
    /// disagree: there is one set of literals, and this is the only way to
    /// flatten it.
    public var text: String {
        ([title, intro] + points + [agreement]).joined(separator: "\n")
    }

    /// The terms as they stand.
    ///
    /// Product copy, and reviewed as such — every hazard here was carried by a
    /// per-technique caution before this screen existed, and `SafetyConsentTests`
    /// pins that each one is still named.
    ///
    /// One instruction to a point, and the reasoning behind it left out: a
    /// warning is obeyed or it is not, and the sentence explaining why it exists
    /// is the one that makes the screen long enough to skim. Each point was
    /// cut to its instruction for that reason — no hazard left, so `version`
    /// stays where it is and nobody is asked to agree twice.
    public static let current = SafetyConsent(
        version: 1,
        title: "Before you start",
        intro: "Breathing exercises suit most people most of the time. These are the few ways they don't.",
        points: [
            "Sit or lie down. Fast breathing can make you faint without warning.",
            "Never in or beside water. Never while driving.",
            "Some exercises are meant to make you drowsy. Do those somewhere you can stay put.",
            "Tingling in your hands or face is ordinary. Lightheadedness means stop and breathe normally.",
            "önd is not medical advice. If you're pregnant, or have a heart or breathing condition, epilepsy, or a history of fainting, ask a doctor first.",
        ],
        agreement: "I understand"
    )
}

/// What somebody agreed to, and when.
///
/// Both halves are the point. A flag saying "consented" is worth nothing a year
/// later, when the question is which words were on the screen — so the exact
/// text is kept beside the timestamp rather than a promise that it could be
/// reconstructed from a version number and the git history of a Swift file.
public struct AgreedSafetyConsent: Codable, Sendable, Equatable {
    /// The `SafetyConsent.version` that was on screen.
    public let version: Int
    /// When the person pressed the button. Never back-filled: a record with an
    /// invented time is worse than no record.
    public let agreedAt: Date
    /// `SafetyConsent.text` as it read at that moment.
    public let text: String

    public init(version: Int, agreedAt: Date, text: String) {
        self.version = version
        self.agreedAt = agreedAt
        self.text = text
    }
}
