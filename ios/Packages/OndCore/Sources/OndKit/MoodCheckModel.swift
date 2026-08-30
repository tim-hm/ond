import Foundation
import Observation

/// One session's mood check: the answer given before the breathing, the one
/// given after, and the rules about when each is taken. Made per session, so
/// nothing here outlives the practice it describes. It takes the write as a
/// parameter instead of holding a `MoodRecorder`, which keeps the ordering
/// rule testable here rather than in a view.
@MainActor
@Observable
public final class MoodCheckModel {
    /// How this person said they felt on the way in, or nil where they were
    /// never asked or skipped the asking.
    public private(set) var before: Mood?

    /// The answer the summary collects, or nil until it is tapped.
    public private(set) var after: Mood?

    /// Whether the "before" choice is resolved, declining it included.
    /// Separate from [`before`] because a decline resolves the choice with no
    /// mood in it. The countdown can finish while this is still false.
    public private(set) var isAsked = false

    public init() {}

    /// What the check is for, said on both halves before either is answered.
    /// Here rather than with the summary's lines, because it belongs to the
    /// question and not to the screen that happens to ask the second half.
    public static let caption = "Context, not a score."

    /// What the summary row says: the pair when there is one, the later
    /// reading alone when the way in was skipped, nil until there is an
    /// answer. It states the two words and never grades the distance between
    /// them.
    public var note: String? {
        guard let after else { return nil }
        guard let before else { return after.title }
        return "\(before.title) before · \(after.title) now"
    }

    /// Takes the answer given before the breathing, writes it, and only then
    /// counts the check as asked. That order is why this is awaited: the first
    /// write of an install opens Health's authorization sheet, and marking the
    /// check answered up front would restart the paused countdown behind it.
    /// The guard stops a second tap writing a contradicting sample.
    public func answerBefore(
        _ mood: Mood,
        writing write: @MainActor (Mood) async -> Void
    ) async {
        guard before == nil, !isAsked else { return }
        before = mood
        await write(mood)
        isAsked = true
    }

    /// Declines the question. Nothing is written: no answer, no sample.
    /// An answer already being written wins, because completing during that
    /// write would restart the countdown behind Health's first-use sheet.
    public func skipBefore() {
        guard before == nil, !isAsked else { return }
        isAsked = true
    }

    /// Takes the answer given after the breathing and writes it. Awaited for
    /// symmetry only; no system sheet can interrupt here. The once-only guard
    /// of [`answerBefore(_:writing:)`] applies.
    public func answerAfter(
        _ mood: Mood,
        writing write: @MainActor (Mood) async -> Void
    ) async {
        guard after == nil else { return }
        after = mood
        await write(mood)
    }
}
