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
    /// which week a session fell in.
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

        let isFirstWeek = week.count == history.count
        let early = week.count { !$0.completed }

        guard week.count > 1 else {
            return oneSession(isFirst: isFirstWeek, endedEarly: early == 1)
        }

        let count = spelled(week.count)
        let counted = isFirstWeek
            ? "\(count) sessions in your first week."
            : "\(count) sessions this week."
        switch early {
        case 0: return counted
        case 1: return counted + " One you ended early — recorded as it happened."
        default: return counted + " \(spelled(early)) you ended early — recorded as they happened."
        }
    }

    /// The week's one session, folded into a single sentence rather than a
    /// count and a suffix: "One session this week. One you ended early" is two
    /// sentences about one thing.
    private static func oneSession(isFirst: Bool, endedEarly: Bool) -> String {
        switch (isFirst, endedEarly) {
        case (true, false): "Your first session is on the record."
        case (true, true): "Your first session, ended early — recorded as it happened."
        case (false, false): "One session this week."
        case (false, true): "One session this week, ended early — recorded as it happened."
        }
    }

    /// "Four" for four, "12" for twelve: the small counts read as prose and
    /// the large ones as the number they are. Capitalised, because every
    /// count here opens a sentence. Foundation spells the word rather than a
    /// table here, on `Duration.spelled`'s argument: a localised build will
    /// not agree with English.
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
