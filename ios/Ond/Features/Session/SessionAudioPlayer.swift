import AVFoundation
import OndKit
import os

/// The audible half of a cue: one soft tone per phase, a rising triad at the end
/// — and, underneath them, what keeps the app alive to play any of it.
///
/// Pitch carries the direction — the inhale sits above the exhale, the two holds
/// sit outside both — so the tones remain distinguishable at a volume low enough
/// to breathe to.
///
/// The phone has no `WKExtendedRuntimeSession` the way the watch does, so the
/// only runtime a backgrounded session can hold is the one `UIBackgroundModes:
/// audio` grants an app that is playing. That budget lasts exactly as long as
/// the playing does, and a cue tone is under a second inside a phase that runs
/// for eleven — so the tones alone buy the first gap and nothing after it. The
/// silence loop below is what makes the gaps the inside of one playback, and it
/// is why this type, not the haptics beside it, is what `playsInBackground`
/// answers for.
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

    private static let completionTone = ToneSynthesizer.wav([
        ToneSynthesizer.Note(440, start: 0, duration: 0.5),
        ToneSynthesizer.Note(554, start: 0.18, duration: 0.5),
        ToneSynthesizer.Note(659, start: 0.36, duration: 0.9),
    ])

    private var players: [PhaseKind: AVAudioPlayer] = [:]
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
    }

    func resume() {
        silence?.play()
    }

    /// Speaks the phase, or sounds it, depending on what there is room for.
    ///
    /// The choice is `Breath.spokenCue`'s, made against the beat as it will
    /// actually be breathed rather than as it was authored — a dial moves these
    /// — and against the slowest voice, so it does not change when somebody
    /// changes voice.
    func play(_ beat: SessionTimeline.Beat) {
        let stem = switch beat.spokenCue {
        case .full: beat.breath.clipName
        case .short: beat.breath.shortClipName
        case .tone: nil as String?
        }
        // `spoken` is empty for a session breathing to tones, so this is the
        // whole condition — no separate check for whether there is a voice.
        if let stem, let player = spoken[stem] {
            // Stopped rather than left to finish: a sentence still being said
            // when the next phase arrives is describing a breath nobody is
            // taking any more.
            talking?.stop()
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
            loaded[stem] = player(for: url)
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
