import Foundation

/// How somebody says they feel, on the one axis Health records — pleasantness.
///
/// Three points rather than a slider. A self-report taken twice around five
/// minutes of breathing is not a fine instrument, and offering more steps than
/// it can carry would be inventing precision — the thing this app is built not
/// to do.
///
/// The case names describe Health's axis while the titles speak in önd's plain
/// register. A sample carries the number and nothing else, and the Health app
/// draws its own vocabulary over its own scale — so the two need not read
/// identically, and neither is translating the other.
///
/// No raw type, unlike every other preference enum here: those have one because
/// their case names are stored keys, and nothing in önd persists a mood. What is
/// recorded is `valence`, written to Health on the device it was tapped on and
/// held nowhere else.
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
