import Foundation

/// The one line of plain language under Home's wordmark: what this week
/// holds, and nothing a person has to brace for.
///
/// It keeps two copy rules at once. The product's copy rule — celebrate
/// consistency, never pressure — is why an empty week is stated without a
/// nudge attached. The session-record rule — an early end is recorded as an
/// early end, nothing else — is why the line volunteers the count rather than
/// leaving it to be discovered on the Progress tab. A sentence, so it lives
/// beside the records it reads rather than in a view the app target has no
/// test bundle to pin.
public enum HomeStateLine {
    /// The line for this moment's history.
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
    ) -> String {
        guard !history.isEmpty else {
            return "Your first session starts the count."
        }

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

        let early = week.count { !$0.completed }

        if week.count == 1 {
            return early == 1
                ? "One session this week, ended early — recorded as it happened."
                : "One session this week."
        }

        let counted = "\(week.count) sessions this week."
        switch early {
        case 0: return counted
        case 1: return counted + " One you ended early — recorded as it happened."
        default: return counted + " \(early) you ended early — recorded as they happened."
        }
    }
}
