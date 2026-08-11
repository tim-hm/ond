import Foundation

/// A voice the session can be spoken in.
///
/// The clips are rendered at build time by `mise run generate:voice` and shipped
/// as AAC — the model that speaks them never reaches the phone. `directory` is
/// the folder they land in, which is Kokoro's own name for the voice pack and so
/// is a key rather than a label: renaming a case must not move a file.
public enum SessionVoice: String, Sendable, Hashable, Codable, CaseIterable {
    case heart
    case michael
    case emma
    case george

    /// Where this voice's clips live under `Resources/Voice`.
    public var directory: String {
        switch self {
        case .heart: "af_heart"
        case .michael: "am_michael"
        case .emma: "bf_emma"
        case .george: "bm_george"
        }
    }

    /// What a picker calls it.
    public var title: String {
        switch self {
        case .heart: "Heart"
        case .michael: "Michael"
        case .emma: "Emma"
        case .george: "George"
        }
    }

    /// Which English it speaks. Said in the picker because it is the difference
    /// somebody is actually choosing between — Kokoro has these two and no other
    /// English at all, so there is no third answer to leave room for.
    public var accent: String {
        switch self {
        case .heart, .michael: "American"
        case .emma, .george: "British"
        }
    }
}

/// What a session with sound on actually plays.
///
/// One choice rather than a switch for "voice or tones" and a second for which
/// voice. Somebody setting this is answering "what do I hear?" once, and two
/// controls to answer it would put the voices behind a toggle that says nothing
/// about them.
///
/// Separate from `SessionCueMode`, which decides *whether* there is sound at
/// all — the same split `HapticStrength` makes against the taps, and for the
/// same reason. Sound is what buys a backgrounded session its runtime, so
/// whether there is any is a question with consequences that picking a voice
/// does not have.
public enum SessionSound: Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// The synthesised tones — one per phase, and what a session played before
    /// it could speak.
    case tones
    case voice(SessionVoice)

    public static var allCases: [SessionSound] {
        [.tones] + SessionVoice.allCases.map(SessionSound.voice)
    }

    public var id: String {
        rawValue
    }

    /// The voice this speaks in, or nil where it does not speak.
    public var voice: SessionVoice? {
        switch self {
        case .tones: nil
        case let .voice(voice): voice
        }
    }

    public var title: String {
        switch self {
        case .tones: "Tones"
        case let .voice(voice): voice.title
        }
    }

    /// Stored flat rather than as a nested enum, because this is a
    /// `UserDefaults` string and a person's setting should survive a case being
    /// added beside it.
    public var rawValue: String {
        switch self {
        case .tones: "tones"
        case let .voice(voice): voice.rawValue
        }
    }

    public init?(rawValue: String) {
        if rawValue == "tones" {
            self = .tones
        } else if let voice = SessionVoice(rawValue: rawValue) {
            self = .voice(voice)
        } else {
            return nil
        }
    }
}
