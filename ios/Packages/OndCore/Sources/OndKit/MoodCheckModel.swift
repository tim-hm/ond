import Foundation
import Observation

/// One session's mood check: the answer given before the breathing, the one
/// given after, and the rules about when each is taken.
///
/// One object for both halves because they are one question asked twice — the
/// pair is the whole point, and the "after" is worth saying back only beside
/// the "before" it followed. Three screens used to hold four flags between
/// them, which meant every rule below lived in a view and none of them could be
/// asserted.
///
/// Per session, not per app. A fresh one is made with the screen and goes with
/// it, so nothing here outlives the practice it describes.
///
/// It holds no `MoodRecorder`, deliberately, and takes the write as a parameter
/// instead. The recorder is the app's — one Health store, handed to every
/// screen through the environment — and this is a value the session screen owns
/// for a few minutes. What the parameter buys is the ordering: the rule about
/// *when* an answer counts as given lives here, where it can be tested, rather
/// than in the view that happens to know where a mood is written. `@MainActor`
/// on the parameter because the recorder is, and a write this could hand off
/// anywhere would be a seam it does not have.
@MainActor
@Observable
public final class MoodCheckModel {
    /// How this person said they felt on the way in, or nil where they were
    /// never asked or skipped the asking.
    public private(set) var before: Mood?

    /// The answer the summary collects, or nil until it is tapped.
    public private(set) var after: Mood?

    /// Whether the "before" half is done, skip included.
    ///
    /// Separate from [`before`] because a skip is an answered check with no
    /// mood in it, and re-asking somebody who declined would make Skip a button
    /// that does nothing.
    public private(set) var isAsked = false

    public init() {}

    /// What the summary's row says once it has its answer: the pair when there
    /// is one, and the reading alone when the way in was skipped. Nil until
    /// there is an answer to say back.
    ///
    /// Stated, never interpreted. No arrow, no "better", no count of the steps
    /// between them — a person can read two words, and grading the distance
    /// would be the invented score this whole surface exists instead of.
    public var note: String? {
        guard let after else { return nil }
        guard let before else { return after.title }
        return "\(before.title) before · \(after.title) now"
    }

    /// Takes the answer given before the breathing, writes it, and only then
    /// counts the check as asked.
    ///
    /// That order is the point of this being awaited. The first write of an
    /// install brings Health's own authorization sheet with it, and the check
    /// is the last gate before the countdown — so marking it answered up front
    /// would clear the gate and start a session counting down behind a modal
    /// nobody asked to have opened.
    ///
    /// `before` is set on the tap rather than on the write, so the scale fills
    /// in the instant it lands. A second tap inside that gap does nothing: the
    /// scale is on its way out under a crossfade and stays live for the length
    /// of it, and without the guard a corrective tap writes a contradicting
    /// sample beside the first that nothing downstream could tell apart.
    public func answerBefore(
        _ mood: Mood,
        writing write: @MainActor (Mood) async -> Void
    ) async {
        guard before == nil, !isAsked else { return }
        before = mood
        await write(mood)
        isAsked = true
    }

    /// Declines the question. Nothing is written, which is the whole of what a
    /// skip means: no prompt, no tap, no sample.
    public func skipBefore() {
        isAsked = true
    }

    /// Takes the answer given after the breathing and writes it.
    ///
    /// Awaited for symmetry rather than for ordering: there is nothing left
    /// here for a system sheet to interrupt, and the row has already said the
    /// tap landed. The same once-only guard [`answerBefore(_:writing:)`]
    /// explains applies.
    public func answerAfter(
        _ mood: Mood,
        writing write: @MainActor (Mood) async -> Void
    ) async {
        guard after == nil else { return }
        after = mood
        await write(mood)
    }
}
