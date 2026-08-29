import AVFoundation
import OndKit
import os

/// The audible half of a cue. Pitch carries the direction — inhale above
/// exhale, holds outside both — so the tones stay distinct at breathing
/// volume. The phone has no `WKExtendedRuntimeSession`; `UIBackgroundModes:
/// audio` grants runtime only while something plays, and a sub-second tone
/// buys none. The silence loop is why `playsInBackground` answers for this type.
@MainActor
final class SessionAudioPlayer {
    private static let logger = Logger(category: "audio")

    /// One second, looped. `AVAudioPlayer` repeats from its own buffer without
    /// the app being woken for it, so the length buys nothing but the 88 KB it
    /// costs to hold.
    private static let silenceLoop = ToneSynthesizer.silence(seconds: 1)

    /// Synthesised once for the process rather than per session: the tones never
    /// vary, and building them is a few hundred thousand `sin` calls that would
    /// otherwise land on the main thread as the player animates in.
    private static let cueTones: [PhaseKind: Data] = [
        .inhale: ToneSynthesizer.wav([ToneSynthesizer.Note(440, duration: 0.55)]),
        .exhale: ToneSynthesizer.wav([ToneSynthesizer.Note(330, duration: 0.7)]),
        .holdIn: ToneSynthesizer.wav([ToneSynthesizer.Note(587, duration: 0.22)]),
        .holdOut: ToneSynthesizer.wav([ToneSynthesizer.Note(262, duration: 0.28)]),
    ]

    /// How loud the stage bell rings under whatever cue shares its instant.
    /// Sounding together is the arrangement, not a collision — but only if the
    /// bell is the quieter of the two and stays out of the voice's register.
    private static let bellVolume: Float = 0.55

    /// How loud a spoken cue plays beside the tones, which sit at 1. Matched
    /// by ear rather than by peak: the render normalises every clip to the
    /// tones' amplitude, but broadband speech at parity arrives over the
    /// breathing rather than under it.
    private static let spokenVolume: Float = 0.7

    /// The bell between stages of a multi-stage practice: a cue says what to
    /// do with this breath, this says the shape of the practice has changed.
    /// Wim Hof's rounds are the case it exists for — nothing else marks the
    /// seam, and the phases either side of it can look alike.
    private static let stageBell = ToneSynthesizer.wav(strike())

    /// The same bell struck twice, for the seam between rounds — the unit
    /// people count, so the more emphatic mark. Two strikes rather than a
    /// second timbre: two unrelated bells are two things to learn. The second
    /// lands while the first still rings, so the pair reads as one gesture.
    private static let roundBell = ToneSynthesizer.wav(strike() + strike(at: 0.65))

    /// One strike: a fundamental with a fifth and an octave over it, the upper
    /// partials shorter than the root so it rings down the way a struck thing
    /// does rather than holding as a chord.
    private static func strike(at start: Double = 0) -> [ToneSynthesizer.Note] {
        [
            ToneSynthesizer.Note(174.6, start: start, duration: 2.4),
            ToneSynthesizer.Note(261.6, start: start, duration: 1.5),
            ToneSynthesizer.Note(349.2, start: start, duration: 0.9),
        ]
    }

    private static let completionTone = ToneSynthesizer.wav([
        ToneSynthesizer.Note(440, start: 0, duration: 0.5),
        ToneSynthesizer.Note(554, start: 0.18, duration: 0.5),
        ToneSynthesizer.Note(659, start: 0.36, duration: 0.9),
    ])

    private var players: [PhaseKind: AVAudioPlayer] = [:]
    private var stageBell: AVAudioPlayer?
    private var roundBell: AVAudioPlayer?
    private var completionPlayer: AVAudioPlayer?
    private var silence: AVAudioPlayer?

    /// The clips of the chosen voice, keyed by the stem they were rendered
    /// under, or empty where the person is breathing to tones.
    private var spoken: [String: AVAudioPlayer] = [:]

    /// The clip currently talking, so the next phase can cut it off rather than
    /// layer over it. A tone never needed this — it is a fifth of a second and
    /// gone — but a sentence runs to two and a half.
    private weak var talking: AVAudioPlayer?

    private let voice: SessionVoice?

    /// - Parameter voice: whose voice speaks the phases, or nil for the tones.
    init(voice: SessionVoice?) {
        self.voice = voice
    }

    func prepare() {
        do {
            // `.playback` so a session keeps its voice with the ring switch off
            // — a phone silenced for a meeting is exactly when someone reaches
            // for this. `.mixWithOthers` because breathing to your own music is
            // a reasonable thing to want, and interrupting it is not our call.
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.logger
                .error("audio session unavailable: \(error.localizedDescription, privacy: .public)")
            return
        }

        players = Self.cueTones.compactMapValues(player(for:))
        stageBell = player(for: Self.stageBell)
        stageBell?.volume = Self.bellVolume
        roundBell = player(for: Self.roundBell)
        roundBell?.volume = Self.bellVolume
        completionPlayer = player(for: Self.completionTone)
        // The tones are loaded either way: a voice still falls back to them for
        // a phase too brief to say anything into.
        if let voice {
            spoken = clips(for: voice)
        }

        silence = player(for: Self.silenceLoop)
        // Endlessly, and started before the first beat: the runtime has to
        // already be held when the person locks the phone, which they may well
        // do during the count-in.
        silence?.numberOfLoops = -1
        silence?.play()
    }

    /// Hands the runtime back for as long as the pause lasts, and takes it again
    /// on the way out. `pause()` rather than `stop()` on the loop: stopping
    /// rewinds it, and this player is never anywhere worth returning to.
    func pause() {
        silence?.pause()
        // The sentence goes quiet with the session. A tone was a fifth of a
        // second and had stopped before a finger left the screen; "breathe out
        // through your left nostril" runs to three, and carrying on instructing
        // somebody who has just paused is the cue talking over them.
        talking?.pause()
        // Not resumed with the others. A sentence resuming mid-phase is still
        // the current instruction; the tail of a bell struck before a pause is
        // nothing anybody is waiting for.
        stageBell?.pause()
        roundBell?.pause()
    }

    /// The clip resumes mid-sentence, which is right: the clock resumes
    /// mid-phase, so the instruction it was giving is still the current one.
    func resume() {
        silence?.play()
        talking?.play()
    }

    /// Speaks the phase, or sounds it, depending on what there is room for.
    /// The choice is `Breath.spokenCue`'s, made against the beat as it will
    /// be breathed — a dial moves these — and against the slowest voice, so
    /// it does not change when somebody changes voice.
    func play(_ beat: SessionTimeline.Beat) {
        // Rung under the cue rather than instead of it: the seam and the breath
        // are two different things to say, and the breath still needs saying.
        if beat.opensStage {
            let bell = beat.opensRound ? roundBell : stageBell
            bell?.currentTime = 0
            bell?.play()
        }

        let stem = beat.clipStem
        // `spoken` is empty for a session breathing to tones, so this is the
        // whole condition — no separate check for whether there is a voice.
        if let stem, let player = spoken[stem] {
            // Cut rather than left to finish: a sentence still talking at the
            // next phase describes a breath nobody is taking. `pause()`, not
            // `stop()`, which undoes `prepareToPlay`: nothing re-warms these,
            // so stopping put a decode back inside every cue after cycle one.
            talking?.pause()
            player.currentTime = 0
            player.play()
            talking = player
            return
        }

        guard let player = players[beat.kind] else { return }
        // Rewound rather than restarted: a cue still ringing when the next phase
        // arrives should be replaced by it, not queued behind it.
        player.currentTime = 0
        player.play()
    }

    func playCompletion() {
        completionPlayer?.currentTime = 0
        completionPlayer?.play()
    }

    func stop() {
        for player in players.values {
            player.stop()
        }
        players.removeAll()
        for player in spoken.values {
            player.stop()
        }
        spoken.removeAll()
        talking = nil
        stageBell?.stop()
        stageBell = nil
        roundBell?.stop()
        roundBell = nil
        completionPlayer?.stop()
        completionPlayer = nil
        // Before the session is deactivated, and not left to deinit: this is the
        // one player that would otherwise go on holding background runtime for a
        // session that has finished.
        silence?.stop()
        silence = nil

        do {
            // Telling other apps we are done is what lets a paused music app
            // resume on its own rather than waiting for the user to notice.
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            Self.logger
                .error(
                    "audio session would not deactivate: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// Loads every clip this voice ships, warmed the way the tones are.
    private func clips(for voice: SessionVoice) -> [String: AVAudioPlayer] {
        var loaded: [String: AVAudioPlayer] = [:]
        for stem in VoiceClips.lines(for: voice).keys {
            guard let url = VoiceClips.url(for: voice, stem: stem) else {
                Self.logger.error("no clip for \(stem, privacy: .public) in this build")
                continue
            }
            let clip = player(for: url)
            clip?.volume = Self.spokenVolume
            loaded[stem] = clip
        }
        return loaded
    }

    /// From the bundle by URL rather than through `Data`: the clips are AAC and
    /// `AVAudioPlayer` decodes a file itself, so reading them into memory first
    /// would buy nothing but the copy.
    private func player(for url: URL) -> AVAudioPlayer? {
        warmed { try AVAudioPlayer(contentsOf: url) }
    }

    private func player(for tone: Data) -> AVAudioPlayer? {
        warmed { try AVAudioPlayer(data: tone) }
    }

    /// One place decides that a player is warmed before its first use, because
    /// forgetting it puts a decode inside the cue it was meant to sound.
    private func warmed(_ make: () throws -> AVAudioPlayer) -> AVAudioPlayer? {
        do {
            let player = try make()
            player.prepareToPlay()
            return player
        } catch {
            Self.logger
                .error("cue would not load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
