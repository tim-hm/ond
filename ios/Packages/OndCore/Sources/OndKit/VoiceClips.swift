import Foundation
import os

/// The committed `voices.json` — what each voice says for each cue, and how
/// long saying it takes. Written beside the clips by `mise run
/// generate:voice`, the only thing that has the model. It lets wording and
/// fit be checked without opening an audio file, on the host, in tests.
public enum VoiceClips {
    private static let logger = Logger(category: "voice-clips")

    /// One rendered line.
    public struct Spoken: Sendable, Hashable, Decodable {
        /// What it says. Held to `Breath.spoken(in:)` by `VoiceCoverageTests`,
        /// which is the only thing standing between a reworded cue and audio
        /// that ships saying the old sentence.
        public let text: String
        /// How long it takes to say, after the render trimmed the model's
        /// padding off it.
        public let seconds: Double
    }

    private struct Entry: Decodable {
        let title: String
        let variant: String
        /// Absent for every voice but the one, so a roster with no default at
        /// all still decodes — `SessionVoice.preferred` falls to the first.
        let `default`: Bool?
        let cues: [String: Spoken]
    }

    /// The manifest as rendered, keyed by voice slug. Empty rather than fatal
    /// when missing, as `CatalogueExport.bundled` is: it is a committed
    /// artefact, so failure means a broken build, which should cost a test
    /// rather than the launch screen. No clips falls back to the tones.
    private static let manifest: [String: Entry] = {
        guard let url = Bundle.module.url(forResource: "Voice/voices", withExtension: "json") else {
            logger.error("no voices.json in the bundle — this build ships no spoken cues")
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url))
        } catch {
            logger
                .error(
                    "voices.json could not be read: \(error.localizedDescription, privacy: .public)"
                )
            return [:]
        }
    }()

    /// Every voice the render shipped. Sorted because JSON objects carry no
    /// order and a picker that reshuffles between launches cannot be learned;
    /// by locale first, then name.
    static let voices: [SessionVoice] = manifest
        .map {
            SessionVoice(
                slug: $0.key,
                title: $0.value.title,
                variant: $0.value.variant,
                isDefault: $0.value.default ?? false
            )
        }
        .sorted { ($0.variant, $0.title) < ($1.variant, $1.title) }

    /// The clips `voice` speaks, keyed by cue name.
    public static func lines(for voice: SessionVoice) -> [String: Spoken] {
        manifest[voice.slug]?.cues ?? [:]
    }

    /// Where the clip of `voice` saying `stem` was rendered to. Here rather
    /// than in the player: `mise run generate:voice` writes the layout and
    /// `Package.swift` copies it, so an app target reaching in would be a
    /// third place to fix when either changes.
    public static func url(for voice: SessionVoice, stem: String) -> URL? {
        Bundle.module.url(forResource: "Voice/\(voice.slug)/\(stem)", withExtension: "m4a")
    }

    /// The longest any voice takes over this line, or nil where none has it.
    /// `spokenCue` measures phases against the slowest voice so which cue a
    /// phase gets is a fact about the exercise, not about who reads it — the
    /// voices span near three to one on a line, and a session must not change
    /// shape when somebody changes voice.
    public static func longest(_ clipName: String) -> Double? {
        manifest.values.compactMap { $0.cues[clipName]?.seconds }.max()
    }

    /// The shortest phase that still gets a whole sentence. Fitting and
    /// having room are not the same: a sentence can fit a 1.5s breath and
    /// still run two-thirds of the phase it describes. Under two seconds a
    /// phase is a beat, and one word is all a beat can carry. Public because
    /// `SpokenCueFitTests` states the rule in these terms.
    public static let sentenceFloor: Double = 2
}

/// Which of a cue's two lengths a phase has room for. Several seeded phases
/// are shorter than the sentence that describes them, and a cue still
/// speaking after its phase ends names a breath nobody is taking — so the
/// sentence falls to the word, and the word to the tone.
public enum SpokenCue: Sendable, Hashable {
    /// "Breathe in through your left nostril".
    case full
    /// "In" — the passage goes unsaid rather than unheard.
    case short
    /// Neither fits; the phase keeps its tone.
    case tone
}

public extension SessionTimeline.Beat {
    /// What this beat has room to be told in. Carried by the beat rather than
    /// recomputed: the player and `SessionView` both need it, and two
    /// surfaces deriving the same answer is how they come to disagree.
    var spokenCue: SpokenCue {
        if let stem = cueRole.sighClipStem {
            let length = VoiceClips.longest(stem) ?? .infinity
            return length <= duration.seconds ? .full : .tone
        }
        return breath.spokenCue(within: duration, in: register)
    }

    /// The clip this beat plays, or nil where it takes its tone instead. One
    /// place decides because the player and the fit rule would eventually
    /// disagree — a beat that stacks on the one before does not name the same
    /// clip as one that starts a breath.
    var clipStem: String? {
        if let stem = cueRole.sighClipStem {
            return spokenCue == .tone ? nil : stem
        }
        return switch spokenCue {
        case .full: breath.clipName(in: register)
        case .short: breath.shortClipName
        case .tone: nil
        }
    }
}

extension BreathCueRole {
    /// The connected clip for a sigh phase, or nil for ordinary cue selection.
    var sighClipStem: String? {
        switch self {
        case .plain: nil
        case .sighOpening: "sigh-in"
        case .sighTopUp: "sigh-and-in"
        case .sighRelease: "sigh-and-out"
        }
    }
}

public extension Breath {
    /// The file stem of the clip that speaks this breath in full.
    ///
    /// Both holds share one clip: they say the same word, because the breath
    /// before a hold is what says which one it is.
    func clipName(in register: CopyRegister = .plain) -> String {
        // Its own clip only where the register has its own words. Every breath
        // a register says nothing about falls through to the plain cue, which
        // is `Breath.spoken(in:)`'s rule rather than a second one kept here —
        // so audio and words fall back together or not at all.
        guard playfulInstruction(in: register) == nil else {
            // Only the two nose breaths were given playful words, so a hold
            // never reaches this line.
            return kind == .inhale ? "inhale-playful" : "exhale-playful"
        }
        return spokenAs.plainClipName
    }

    /// The stem of the plain cue for this breath.
    ///
    /// Read through `spokenAs`, so the mouth cases below are unreachable as
    /// themselves — they have already become nose breaths, which is what leaves
    /// the audio nine cues rather than eleven.
    private var plainClipName: String {
        switch self {
        case .inhale(.nose), .inhale(.mouth): "inhale"
        case .inhale(.leftNostril): "inhale-left-nostril"
        case .inhale(.rightNostril): "inhale-right-nostril"
        case .exhale(.nose), .exhale(.mouth): "exhale"
        case .exhale(.leftNostril): "exhale-left-nostril"
        case .exhale(.rightNostril): "exhale-right-nostril"
        case .holdIn, .holdOut: "hold"
        }
    }

    /// The file stem of the clip that speaks it in one word.
    ///
    /// A hold has no shorter form to fall back to — "Hold" is already the whole
    /// of it — so it names the same clip, which is what makes a hold either
    /// speak or take the tone with nothing in between.
    var shortClipName: String {
        switch self {
        case .inhale: "short-in"
        case .exhale: "short-out"
        case .holdIn, .holdOut: "hold"
        }
    }

    /// Which cue fits inside `duration`, measured against the slowest voice so
    /// the answer does not depend on which one is speaking. The comparison is
    /// against the phase as it will be breathed — a dial can move every
    /// duration here. A phase under `VoiceClips.sentenceFloor` takes the word
    /// even where the sentence would have fitted.
    func spokenCue(
        within duration: Duration,
        in register: CopyRegister = .plain
    ) -> SpokenCue {
        let room = duration.seconds

        let sentence = VoiceClips.longest(clipName(in: register)) ?? .infinity
        if room > VoiceClips.sentenceFloor, sentence <= room {
            return .full
        }
        if let short = VoiceClips.longest(shortClipName), short <= room {
            return .short
        }
        return .tone
    }
}
