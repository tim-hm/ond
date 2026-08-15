/// Which cues accompany the animation.
///
/// Haptics and audio are separable because the situations differ: a phone face
/// down in a pocket needs the taps and nothing else, a quiet office needs
/// neither, and both need the same session underneath.
public enum SessionCueMode: String, Sendable, CaseIterable, Identifiable {
    case hapticsAndAudio
    case haptics
    case visualOnly

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .hapticsAndAudio: "Haptics & sound"
        case .haptics: "Haptics only"
        case .visualOnly: "Visual only"
        }
    }

    public var playsHaptics: Bool {
        self != .visualOnly
    }

    public var playsAudio: Bool {
        self == .hapticsAndAudio
    }

    /// What this mode costs once the screen goes off, said where the mode is
    /// chosen rather than discovered three phases into a practice.
    ///
    /// Observed platform behaviour, not a preference: iOS withholds haptics from
    /// a locked device however much background runtime the app holds, so sound is
    /// the only channel that follows somebody out — `SessionCues.playsInBackground`
    /// carries the device finding this rests on. Exhaustive so a fourth mode
    /// cannot be added without answering the question.
    public var screenOffNote: String {
        switch self {
        case .hapticsAndAudio:
            "iPhone haptics aren't supported when the screen is off — you'll hear the session but not feel it."
        case .haptics:
            "iPhone haptics aren't supported when the screen is off, so the session pauses and says so."
        case .visualOnly:
            "The session pauses when you leave the app, and says so."
        }
    }
}
