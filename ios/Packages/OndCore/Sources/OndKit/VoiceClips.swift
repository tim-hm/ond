import Foundation
import os

/// The committed `voices.json` — what each voice says for each cue, and how long
/// saying it takes.
///
/// Written beside the clips by `mise run generate:voice`, which is the only
/// thing that has the model. It exists so the two questions the app needs
/// answering about a clip — does this still say the right words, and will it fit
/// inside this phase — can both be answered without opening an audio file, on
/// the host, in the test suite.
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

    /// The manifest as rendered, keyed by voice slug.
    ///
    /// Empty rather than fatal when the resource is missing, for the reason
    /// `CatalogueExport.bundled` is: it is a committed artefact, so a failure
    /// here means a broken build, and a broken build should cost a test rather
    /// than everybody's launch screen. A session with no clips falls back to the
    /// tones, which is a session that predates this feature.
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

    /// Every voice the render shipped, grouped by locale and named within it.
    ///
    /// Sorted at all because JSON objects carry no order, and a picker that
    /// reshuffles between launches is a picker nobody can learn. By locale
    /// first because that is the choice somebody makes before they get to the
    /// names, once there is more than one to make.
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

    /// Where the clip of `voice` saying `stem` was rendered to.
    ///
    /// Here rather than in the player, because the folder layout is this
    /// module's business: `mise run generate:voice` writes it and `Package.swift`
    /// copies it, both of which are OndKit's, and an app target reaching into
    /// `Voice/<pack>/<stem>.m4a` itself would be a third place to fix when
    /// either changes.
    public static func url(for voice: SessionVoice, stem: String) -> URL? {
        Bundle.module.url(forResource: "Voice/\(voice.slug)/\(stem)", withExtension: "m4a")
    }

    /// The longest any voice takes over this line, or nil where none of them
    /// has it.
    ///
    /// What `spokenCue` measures a phase against, so that which cue a phase gets
    /// is a fact about the exercise rather than about who is reading it. The
    /// voices are asked for a common pace but do not answer at identical
    /// lengths — "Breathe out" spans 0.92s to 1.19s across the four — and
    /// against Wim Hof's one-second exhale that spread is the difference between
    /// hearing the sentence and hearing the word. Deciding on the slowest costs
    /// a quick voice some headroom it did not need, and buys a session that does
    /// not change shape when somebody changes voice.
    public static func longest(_ clipName: String) -> Double? {
        manifest.values.compactMap { $0.cues[clipName]?.seconds }.max()
    }
}

/// Which of a cue's two lengths a phase has room for.
///
/// Three of the seeded catalogue's phases are shorter than the sentence that
/// describes them: physiological sigh's top-up inhale runs 0.7s and bellows
/// breath a second each way, against a cue of about one. A cue still speaking
/// when the phase it describes has ended is naming a breath nobody is taking,
/// which is the one thing a guide cannot get wrong — so a phase that cannot hold
/// the sentence gets the word, and a phase that cannot hold the word gets the
/// tone it always had.
public enum SpokenCue: Sendable, Hashable {
    /// "Breathe in through your left nostril".
    case full
    /// "In" — the passage goes unsaid rather than unheard.
    case short
    /// Neither fits; the phase keeps its tone.
    case tone
}

public extension SessionTimeline.Beat {
    /// What this beat has room to be told in.
    ///
    /// Asked of the beat rather than worked out again by whoever is speaking it.
    /// The player needs it to choose a clip and `SessionView` needs it to decide
    /// whether VoiceOver still has something to say, and two surfaces deriving
    /// the same answer from the model is how they come to disagree — the reason
    /// every other fact a beat carries is carried rather than recomputed.
    var spokenCue: SpokenCue {
        breath.spokenCue(within: duration, in: register)
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
        if playfulInstruction(in: register) != nil {
            switch kind {
            case .inhale: return "inhale-playful"
            case .exhale: return "exhale-playful"
            case .holdIn, .holdOut: break
            }
        }

        switch spokenAs {
        case .inhale(.leftNostril): return "inhale-left-nostril"
        case .inhale(.rightNostril): return "inhale-right-nostril"
        case .exhale(.leftNostril): return "exhale-left-nostril"
        case .exhale(.rightNostril): return "exhale-right-nostril"
        case .holdIn, .holdOut: return "hold"
        // The mouth never reaches here as itself: `spokenAs` has already sent
        // it to the nose, which is what leaves the audio nine cues rather than
        // eleven.
        case .inhale(.nose), .inhale(.mouth): return "inhale"
        case .exhale(.nose), .exhale(.mouth): return "exhale"
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
    /// the answer does not depend on which one is speaking.
    ///
    /// The comparison is against the phase as it will actually be breathed, not
    /// as it was authored: every duration here is one a dial can move, and a
    /// sentence that fits box breathing's four seconds does not fit it dialled
    /// down to three.
    func spokenCue(within duration: Duration, in register: CopyRegister = .plain) -> SpokenCue {
        let room = duration.seconds

        if let full = VoiceClips.longest(clipName(in: register)), full <= room {
            return .full
        }
        if let short = VoiceClips.longest(shortClipName), short <= room {
            return .short
        }
        return .tone
    }
}
