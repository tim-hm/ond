import Foundation

/// What a session says when it ends: the sentence that leads the summary, the
/// line under it, and which of the three figures have anything in them. Here
/// rather than in either summary screen, so the phone and the wrist cannot
/// drift apart on the one copy rule that matters — celebrate what happened,
/// never grade it. The cases are in docs/product/session-summary.md.
public enum SessionSummaryLines {
    /// The screen's one sentence. Two forms rather than one: they describe two
    /// different records, not two different people. A session ended by hand is
    /// told it is a session, which is the only doubt it leaves. The playful
    /// register says the same two facts to a small child.
    public static func headline(for record: SessionRecord, register: CopyRegister) -> String {
        switch register {
        case .plain: record.completed ? "Nicely done." : "That's a session."
        case .playful: record.completed ? "You did it." : "That was breathing."
        }
    }

    /// The line under the headline. It names the exercise where the session ran
    /// to its end and the ending where it did not: the slot holds one line, and
    /// an early end is the fact that has to survive it. A playful session is
    /// breathed with somebody, so its finished line says so.
    public static func note(
        for record: SessionRecord,
        exercise: String,
        register: CopyRegister
    ) -> String {
        switch register {
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
