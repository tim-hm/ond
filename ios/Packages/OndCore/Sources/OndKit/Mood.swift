import Foundation

/// How somebody says they feel, on the one axis Health records: pleasantness.
/// Three points, not a slider. A check-in around five minutes of breathing
/// cannot carry more. No raw value, unlike the stored preference enums here,
/// because nothing persists a mood. Only `valence` reaches Health, on the
/// device it was tapped on.
public enum Mood: Sendable, CaseIterable, Identifiable {
    /// A below-neutral check-in, recorded as negative valence.
    case unpleasant
    /// The midpoint of Health's pleasantness scale.
    case neutral
    /// An above-neutral check-in, recorded as positive valence.
    case pleasant

    /// Stable identity for the three mood controls.
    public var id: Self {
        self
    }

    /// Where this sits on Health's own -1...1 pleasantness axis, which is the
    /// only number a State of Mind sample carries.
    public var valence: Double {
        switch self {
        case .unpleasant: -0.5
        case .neutral: 0
        case .pleasant: 0.5
        }
    }

    /// What the point is called on screen, and in the one line the summary
    /// reads a pair back in.
    public var title: String {
        switch self {
        case .unpleasant: "Not good"
        case .neutral: "Okay"
        case .pleasant: "Good"
        }
    }
}
