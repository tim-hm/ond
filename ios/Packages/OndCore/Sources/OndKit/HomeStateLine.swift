import Foundation

/// Home's one true sentence: what this week holds, and nothing a person has
/// to brace for.
///
/// It keeps two copy rules at once. The product's copy rule — celebrate
/// consistency, never pressure — is why an empty week is stated without a
/// nudge attached and why no line here is ever a streak. The session-record
/// rule — an early end is recorded as an early end, nothing else — is why the
/// line volunteers the count rather than leaving it to be discovered on the
/// Progress tab. A sentence, so it lives beside the records it reads rather
/// than in a view the app target has no test bundle to pin.
///
/// The written cases, which this type owns:
///
/// | case          | when                                    | line
///   |
/// |---------------|-----------------------------------------|----------------------------------------|
/// | nothing yet   | no history                              | nothing — the layout closes up
///   |
/// | broken week   | history, none of it this week           | "Nothing this week yet."
///   |
/// | first week    | every session ever falls in this week   | "… in your first week." / "… is on
/// the record." |
/// | a week        | otherwise                               | "Four sessions this week."
///   |
/// | ended early   | suffix on any counted week              | "One you ended early — recorded as
/// it happened." |
///
/// Nothing yet says nothing rather than inviting, because the only true thing
/// about an empty history is that it is empty, and the button below the line
/// is already the invitation.
public enum HomeStateLine {
    /// The line for this moment's history, or nil when there is nothing true
    /// to say.
    ///
    /// - Parameters:
    ///   - history: every session recorded on this device, in any order.
    ///   - now: the instant whose week the line describes.
    ///   - calendar: carries the time zone the week is counted in — the
    ///     `JourneyStats` default, so Home and Progress cannot disagree about
    ///     which week a session fell in.
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
    /// count here opens a sentence.
    static func spelled(_ count: Int) -> String {
        guard (1 ... 9).contains(count) else { return String(count) }
        let words = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        return words[count - 1]
    }
}
