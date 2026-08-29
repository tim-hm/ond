import Foundation

/// A voice the session can be spoken in. Read from `voices.json` rather than
/// declared here: `mise run generate:voice` decides every field, so swapping
/// or adding a voice is a manifest edit and a re-render — nothing in the app
/// knows which ones exist. `slug` is the identity: the clips' folder and the
/// stored setting, so it must survive a supplier renaming a voice.
public struct SessionVoice: Sendable, Hashable, Identifiable {
    /// Where this voice's clips live under `Resources/Voice`, and what
    /// `SessionSound` persists.
    public let slug: String
    /// What a picker calls it — the supplier's name for the voice, carried
    /// through the render.
    public let title: String
    /// The locale it was rendered for, as the manifest names it: `en-GB`.
    public let variant: String

    /// The region this voice reads in, named the way the system names regions.
    /// Derived from `variant`: a manifest field would be a second name, free
    /// to disagree and untranslated. Looked up in the ISO list rather than
    /// parsed — `Locale` answers well-formed nonsense with "Unknown Region",
    /// never nil — so an unknown tag shows as itself and names the TOML to fix.
    public var region: String {
        guard let code = Locale(identifier: variant).region,
              Self.realRegions.contains(code),
              let named = Locale.current.localizedString(forRegionCode: code.identifier)
        else {
            return variant
        }
        return named
    }

    /// The ISO regions, as a set. `Locale.Region.isoRegions` is an array of
    /// around 250, and this is read once per row every time the picker draws.
    private static let realRegions = Set(Locale.Region.isoRegions)
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

/// What a session with sound on actually plays. One choice rather than a
/// "voice or tones" switch plus a voice picker: somebody answers "what do I
/// hear?" once. Separate from `SessionCueMode`, which decides *whether* there
/// is sound at all — sound buys a backgrounded session its runtime, a
/// consequence picking a voice does not have.
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

    /// What a picker calls it. The region is part of the name because the
    /// roster is sorted by it, and a list that groups by something it never
    /// shows is a list nobody can read.
    public var title: String {
        switch self {
        case .tones: "Tones"
        case let .voice(voice): "\(voice.title) — \(voice.region)"
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
