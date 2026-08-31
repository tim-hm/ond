import os

/// The tap a phase plays, named by the catalogue's `haptic_pattern` column.
/// A closed set rather than free text: an id nothing here names would
/// otherwise be a silent failure.
public enum HapticPattern: String, Sendable, Equatable {
    /// The onset and envelope the beat derives for itself. What every phase
    /// naming nothing plays.
    case standard
    /// A stacked inhale: a lighter, sharper onset, and an envelope that
    /// resumes from the breath before it rather than from empty lungs.
    case sip
    /// A resisted breath out: a firmer onset, and an envelope that holds
    /// instead of decaying. A fading cue tells you to stop pushing.
    case press
    /// The onset alone. Under a second and a half an envelope is noise with a
    /// tap buried in it.
    case drum
    /// The onset, then a reminder tap while the hold runs. For a retention
    /// long enough to lose track of; inside seven seconds it would be a nag.
    case longHold = "long-hold"

    /// `id` as one of these, or `standard` where the catalogue named something
    /// this build does not know. Logged here because this is the boundary the
    /// name crosses: the timeline asks while it lays a plan out, once a stage
    /// rather than once a cue.
    static func resolved(_ id: String?) -> Self {
        guard let id else { return .standard }
        guard let pattern = Self(rawValue: id) else {
            logger.notice("unknown haptic pattern \(id, privacy: .public); playing standard")
            return .standard
        }
        return pattern
    }

    private static let logger = Logger(category: "haptics")
}
