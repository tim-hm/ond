import AVFoundation
import OndKit
import os

/// The audible half of a cue: tones, and the bells that mark a seam. Pitch
/// carries the direction — inhale above exhale, holds outside both. The phone
/// has no `WKExtendedRuntimeSession`, and `UIBackgroundModes: audio` grants
/// runtime only while something plays, which a sub-second tone does not. The
/// silence loop is why `playsInBackground` answers for this type.
@MainActor
final class SessionAudioPlayer {
    private static let logger = Logger(category: "audio")

    /// How loud the stage bell rings under whatever cue shares its instant.
    /// Sounding together is the arrangement, not a collision — but only if the
    /// bell is the quieter of the two.
    private static let bellVolume: Float = 0.55

    private var players: [PhaseKind: AVAudioPlayer] = [:]
    private var stageBell: AVAudioPlayer?
    private var roundBell: AVAudioPlayer?
    private var completionPlayer: AVAudioPlayer?
    private var silence: AVAudioPlayer?

    init() {
        // Here rather than in `prepare()`, which runs on the frame the count-in
        // ends: the buffers are lazy, so the first session of a launch would
        // synthesise all of them on the main actor at exactly that moment. The
        // count-in is the time this buys.
        Task.detached(priority: .userInitiated) {
            SessionTones.warm()
        }
    }

    func prepare() {
        do {
            // `.playback` so a session keeps its cues with the ring switch off
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

        players = SessionTones.cue.compactMapValues(player(for:))
        stageBell = player(for: SessionTones.stage)
        stageBell?.volume = Self.bellVolume
        roundBell = player(for: SessionTones.round)
        roundBell?.volume = Self.bellVolume
        completionPlayer = player(for: SessionTones.completion)

        silence = player(for: SessionTones.silenceLoop)
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
        // Paused but never resumed: the tail of a bell struck before a pause is
        // nothing anybody is waiting for.
        stageBell?.pause()
        roundBell?.pause()
    }

    func resume() {
        silence?.play()
    }

    /// Sounds the phase, and rings the seam under it where there is one.
    func play(_ beat: SessionTimeline.Beat) {
        // Rung under the cue rather than instead of it: the seam and the breath
        // are two different things to say, and the breath still needs saying.
        if beat.opensStage {
            let bell = beat.opensRound ? roundBell : stageBell
            bell?.currentTime = 0
            bell?.play()
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

    /// Warmed before its first use: skipping that puts a decode inside the
    /// cue it was meant to sound.
    private func player(for tone: Data) -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(data: tone)
            player.prepareToPlay()
            return player
        } catch {
            Self.logger
                .error("cue would not load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// The session's cue tones, synthesised once for the process rather than per
/// session: the tones never vary, and building them is a few hundred thousand
/// `sin` calls. Outside `SessionAudioPlayer` because that type is `@MainActor`
/// and its statics with it, and these have to be reachable from the warm-up
/// that runs off the main actor.
enum SessionTones {
    /// One second, looped. `AVAudioPlayer` repeats from its own buffer without
    /// the app being woken for it, so the length buys nothing but the 88 KB it
    /// costs to hold.
    static let silenceLoop = ToneSynthesizer.silence(seconds: 1)

    static let cue: [PhaseKind: Data] = [
        .inhale: ToneSynthesizer.wav([ToneSynthesizer.Note(440, duration: 0.55)]),
        .exhale: ToneSynthesizer.wav([ToneSynthesizer.Note(330, duration: 0.7)]),
        .holdIn: ToneSynthesizer.wav([ToneSynthesizer.Note(587, duration: 0.22)]),
        .holdOut: ToneSynthesizer.wav([ToneSynthesizer.Note(262, duration: 0.28)]),
    ]

    /// The bell between stages of a multi-stage practice: a cue says what to
    /// do with this breath, this says the shape of the practice has changed.
    /// Wim Hof's rounds are the case it exists for — nothing else marks the
    /// seam, and the phases either side of it can look alike.
    static let stage = ToneSynthesizer.wav(strike())

    /// The same bell struck twice, for the seam between rounds — the unit
    /// people count, so the more emphatic mark. Two strikes rather than a
    /// second timbre: two unrelated bells are two things to learn. The second
    /// lands while the first still rings, so the pair reads as one gesture.
    static let round = ToneSynthesizer.wav(strike() + strike(at: 0.65))

    static let completion = ToneSynthesizer.wav([
        ToneSynthesizer.Note(440, start: 0, duration: 0.5),
        ToneSynthesizer.Note(554, start: 0.18, duration: 0.5),
        ToneSynthesizer.Note(659, start: 0.36, duration: 0.9),
    ])

    /// Touches every buffer, so whoever calls this pays for the synthesis
    /// instead of the first cue that reads one. Every buffer above is named
    /// here: a tone left out is synthesised on the main actor instead.
    static func warm() {
        _ = silenceLoop
        _ = cue
        _ = stage
        _ = round
        _ = completion
    }

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
}
