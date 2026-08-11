import Foundation

/// A voice the session can be spoken in.
///
/// Read from `voices.json` rather than declared here, because every field of it
/// is decided by the render: `mise run generate:voice` picks the supplier's
/// voice, records what it is called, and writes the clips to a folder named by
/// `slug`. Swapping a voice for a better one, or adding another, is then a
/// manifest edit and a re-render — nothing in the app knows which ones exist.
///
/// `slug` is the identity, not the title: it is the folder the clips live in and
/// the string a person's setting is stored as, so it must survive a supplier
/// changing a voice's name.
public struct SessionVoice: Sendable, Hashable, Identifiable {
    /// Where this voice's clips live under `Resources/Voice`, and what
    /// `SessionSound` persists.
    public let slug: String
    /// What a picker calls it — the supplier's name for the voice, carried
    /// through the render.
    public let title: String
    /// The locale it was rendered for, as the manifest names it: `en-GB`.
    public let variant: String
    /// Whether a fresh install breathes to this one. Decided in the manifest
    /// and checked there — the render refuses to run unless exactly one voice
    /// claims it — so which voice somebody meets first is data like the rest of
    /// the roster, not a name spelled into Swift.
    public let isDefault: Bool

    public var id: String {
        slug
    }

    /// Every voice this build shipped clips for, in a stable order.
    ///
    /// Empty where the render has not been run, which leaves `SessionSound` with
    /// only its tones — a session that predates this feature rather than a
    /// broken one.
    public static var all: [SessionVoice] {
        VoiceClips.voices
    }

    /// The shipped voice with this slug, or nil where a stored setting names one
    /// this build no longer has.
    public static func named(_ slug: String) -> SessionVoice? {
        all.first { $0.slug == slug }
    }

    /// The voice a fresh install breathes to, or nil where this build shipped
    /// no clips at all — which leaves the tones, as it did before there were
    /// any voices to prefer.
    public static var preferred: SessionVoice? {
        all.first(where: \.isDefault) ?? all.first
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
public enum SessionSound: Sendable, Hashable, CaseIterable, Identifiable {
    /// The synthesised tones — one per phase, and what a session played before
    /// it could speak.
    case tones
    case voice(SessionVoice)

    /// Tones first, then whatever the render shipped. Data rather than a fixed
    /// list, so this is `CaseIterable` in the sense a picker needs and not in
    /// the sense the compiler could check.
    public static var allCases: [SessionSound] {
        [.tones] + SessionVoice.all.map(SessionSound.voice)
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

    /// What a picker calls it.
    ///
    /// The name alone. It carried the accent too while the roster held two
    /// Englishes; both readers are British now, so "Faye — British" beside
    /// "George — British" was a column that said the same thing twice. When a
    /// second English arrives, this is where it goes back.
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
        case let .voice(voice): voice.slug
        }
    }

    /// Nil for a slug this build has no clips for, which is what a voice
    /// dropped from the manifest looks like to somebody who had it selected.
    /// `SessionSettings` reads that as the tones.
    public init?(rawValue: String) {
        if rawValue == "tones" {
            self = .tones
        } else if let voice = SessionVoice.named(rawValue) {
            self = .voice(voice)
        } else {
            return nil
        }
    }
}
