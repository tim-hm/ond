import Foundation

/// How somebody says they feel, on the one axis Health records: pleasantness.
/// Five points, not a slider, and an odd count so that no change is sayable.
/// No raw value, unlike the stored preference enums here, because nothing
/// persists a mood. Only `valence` reaches Health, on the device it was
/// tapped on.
public enum Mood: Sendable, CaseIterable, Identifiable {
    /// The bottom of Health's pleasantness axis.
    case veryUnpleasant
    /// A below-neutral check-in, recorded as negative valence.
    case unpleasant
    /// The midpoint of Health's pleasantness scale.
    case neutral
    /// An above-neutral check-in, recorded as positive valence.
    case pleasant
    /// The top of Health's pleasantness axis.
    case veryPleasant

    /// The two ends, named so that a scale can label them without indexing
    /// into `allCases` and unwrapping what it finds.
    public static let lowest: Mood = .veryUnpleasant
    public static let highest: Mood = .veryPleasant

    /// Stable identity for the five mood controls.
    public var id: Self {
        self
    }

    /// Where this sits on Health's own -1...1 pleasantness axis, which is the
    /// only number a State of Mind sample carries.
    public var valence: Double {
        switch self {
        case .veryUnpleasant: -1
        case .unpleasant: -0.5
        case .neutral: 0
        case .pleasant: 0.5
        case .veryPleasant: 1
        }
    }

    /// The numeral the scale draws. Written out per case rather than taken
    /// from an index, so a case added in the wrong place cannot renumber the
    /// others silently.
    public var position: Int {
        switch self {
        case .veryUnpleasant: 1
        case .unpleasant: 2
        case .neutral: 3
        case .pleasant: 4
        case .veryPleasant: 5
        }
    }

    /// What the point is called: the ends label the scale, every point labels
    /// itself for VoiceOver, and the summary reads a pair back in these words.
    public var title: String {
        switch self {
        case .veryUnpleasant: "Bad"
        case .unpleasant: "Not good"
        case .neutral: "Okay"
        case .pleasant: "Good"
        case .veryPleasant: "Great"
        }
    }
}
