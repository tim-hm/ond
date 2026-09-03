import Foundation

/// Home's one true sentence: what this week holds, and nothing to brace for.
/// Two copy rules at once: celebrate consistency, never pressure — an empty
/// week is stated without a nudge and no line is ever a streak — and an early
/// end is recorded as an early end, so the line volunteers the count. An
/// empty history says nothing at all: the button below is the invitation.
public enum HomeStateLine {
    /// The line for this moment's history, or nil when there is nothing true
    /// to say. `calendar` carries the time zone the week is counted in — the
    /// `JourneyStats` default, so Home and Progress cannot disagree about
    /// which week a session fell in. The cases, their strings and the order
    /// they are tested in are in docs/product/home-sentence.md.
    public static func line(
        history: [SessionRecord],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard !history.isEmpty else { return nil }

        // One calendar decomposition for the whole history: this runs on
        // every Home body pass, and asking the calendar per record would put
        // a component breakdown inside the loop. Half-open by hand, because
        // `DateInterval.contains` includes its end and a session stamped
        // exactly on the boundary would count in two weeks.
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let week = history.filter { record in
            guard let interval else { return false }
            return interval.start <= record.startedAt && record.startedAt < interval.end
        }
        guard !week.isEmpty else { return "Nothing this week yet." }

        if week.count == 1 {
            let lone = week[0]
            return oneSession(
                standing(of: lone.startedAt, in: history, calendar: calendar),
                endedEarly: !lone.completed
            )
        }

        let early = week.count { !$0.completed }
        let count = spelled(week.count)
        let counted = week.count == history.count
            ? "\(count) sessions in your first week"
            : "\(count) sessions this week"
        // One sentence, as the week's single session already is. The early
        // ends were a second sentence appended to the first, which reads as an
        // afterthought about a fact this line is stating on purpose.
        switch early {
        case 0: return counted + "."
        case 1: return counted + ", one ended early."
        default: return counted + ", \(spelled(early).lowercased()) ended early."
        }
    }

    /// Where the week's one session sits against everything recorded before
    /// it. A first session has nothing behind it, so it can never also be a
    /// return: the two are exclusive by definition, not by precedence.
    private enum Standing {
        case first
        case returning
        case ordinary
    }

    /// The smallest gap that always holds a blank calendar week, so a single
    /// skipped week never reads as an absence. Argued in
    /// docs/product/home-sentence.md.
    private static let returnGapDays = 14

    /// The gap is whole calendar days, not elapsed time: a late-night session
    /// and an early-morning one are a day apart, however few hours separate
    /// them. `previous` is read off the dates, never the array's order, which
    /// callers sort both ways.
    private static func standing(
        of session: Date,
        in history: [SessionRecord],
        calendar: Calendar
    ) -> Standing {
        let earlier = history.lazy.filter { $0.startedAt < session }.map(\.startedAt)
        guard let previous = earlier.max() else { return .first }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: previous),
            to: calendar.startOfDay(for: session)
        ).day ?? 0
        return days >= returnGapDays ? .returning : .ordinary
    }

    /// The week's one session, folded into a single sentence rather than a
    /// count and a suffix: "One session this week. One you ended early" is two
    /// sentences about one thing.
    private static func oneSession(_ standing: Standing, endedEarly: Bool) -> String {
        switch (standing, endedEarly) {
        case (.first, false): "Your first session is recorded."
        case (.first, true): "Your first session, ended early."
        case (.returning, false): "Your first session back is recorded."
        case (.returning, true): "Your first session back, ended early."
        case (.ordinary, false): "One session this week."
        case (.ordinary, true): "One session this week, ended early."
        }
    }

    /// "Four" for four, "12" for twelve: the small counts read as prose and
    /// the large ones as the number they are. Capitalised for the count that
    /// opens the sentence; the early-end count lowercases it. Foundation
    /// spells the word rather than a table here, on `Duration.spelled`'s
    /// argument: a localised build will not agree with English.
    static func spelled(_ count: Int) -> String {
        guard (1 ... 9).contains(count),
              let word = spellOut.string(from: NSNumber(value: count))
        else {
            return String(count)
        }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    private static let spellOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter
    }()
}
