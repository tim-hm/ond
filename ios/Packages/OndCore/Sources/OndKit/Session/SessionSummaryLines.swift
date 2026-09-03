import Foundation

/// What a session says when it ends: the sentence that leads the summary, the
/// line under it, and which of the three figures have anything in them. Here
/// rather than in either summary screen, so the phone and the wrist cannot
/// drift apart on the one copy rule that matters — celebrate what happened,
/// never grade it. The cases are in docs/product/session-summary.md.
public enum SessionSummaryLines {
    /// Which session the summary is speaking about. A session ended by hand
    /// inside `SessionRecord.minimumRecordedDuration` is discarded, and it
    /// still reaches this screen: a screen that vanished instead would be
    /// indistinguishable from a crash.
    public enum Outcome: Equatable, Sendable {
        case kept(SessionRecord)
        case discarded

        /// What was kept, or nil where nothing was. The figures, the pulse
        /// curve and the mood question all speak about a session that exists.
        public var record: SessionRecord? {
            guard case let .kept(record) = self else { return nil }
            return record
        }
    }

    /// The screen's one sentence. Plain says the same words however the
    /// session ended: the note under it states which, and a headline that
    /// differed would grade the session. Playful keeps two, because a child is
    /// spoken to rather than told. Discarded is one line in both — there is no
    /// playful way to say nothing was kept.
    public static func headline(for outcome: Outcome, register: CopyRegister) -> String {
        guard case let .kept(record) = outcome else { return "Too short to keep." }

        return switch register {
        case .plain: "All done."
        case .playful: record.completed ? "You did it." : "That was breathing."
        }
    }

    /// The line under the headline. It names the exercise where the session ran
    /// to its end and the ending where it did not: the slot holds one line, and
    /// an early end is the fact that has to survive it. A playful session is
    /// breathed with somebody, so its finished line says so.
    public static func note(
        for outcome: Outcome,
        exercise: String,
        register: CopyRegister
    ) -> String {
        guard case let .kept(record) = outcome else { return "Nothing was recorded." }

        return switch register {
        case .plain:
            record.completed
                ? "You finished \(exercise)."
                : "You ended this session early."
        case .playful:
            record.completed
                ? "You breathed \(exercise) together."
                : "You stopped this one early."
        }
    }

    /// One figure under the slots: a value and what it counts.
    public struct Figure: Equatable, Identifiable, Sendable {
        public let label: String
        public let value: String

        /// The label, which is unique within a row by construction.
        public var id: String {
            label
        }
    }

    /// The figures with something in them, in reading order. A count of zero is
    /// dropped: it says nothing the time does not already say, and a row of
    /// zeroes turns a screen that refuses to score into a scorecard. Time is
    /// always shown, and labelled `time` rather than `minutes` — a session of
    /// forty seconds under a label saying minutes is a small lie.
    public static func figures(for record: SessionRecord) -> [Figure] {
        [
            counted(record.cyclesCompleted, of: "cycle"),
            Figure(
                label: "time",
                value: record.duration.formatted(.time(pattern: .minuteSecond))
            ),
            counted(record.breathCount, of: "breath"),
        ].compactMap(\.self)
    }

    /// One counted figure, or nothing at all where the count is zero. Public
    /// because Progress speaks the same figure in its history row, and the app
    /// target has no tests of its own — a second copy of drop-zero-and-
    /// pluralise is a copy nothing measures.
    public static func counted(_ count: Int, of thing: String) -> Figure? {
        guard count > 0 else { return nil }
        return Figure(label: count == 1 ? thing : "\(thing)s", value: "\(count)")
    }
}
