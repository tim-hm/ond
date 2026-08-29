import OndKit

/// The app's implementation of `SessionCueing`: whichever cue channels the
/// person has switched on, driven from the one session loop. The mode resolves
/// once, at session start, into "which controllers exist" — every call site is
/// a nil-check, and a mode change mid-session cannot leave the audio session
/// half-configured.
@MainActor
final class SessionCues: SessionCueing {
    private let haptics: HapticController?
    private let audio: SessionAudioPlayer?

    init(mode: SessionCueMode, strength: HapticStrength, sound: SessionSound) {
        haptics = mode.playsHaptics ? HapticController(strength: strength) : nil
        audio = mode.playsAudio ? SessionAudioPlayer(voice: sound.voice) : nil
    }

    /// Sound is the whole of the answer: background runtime is granted for
    /// playing audio, so a soundless session has no honest claim to it — and
    /// the claim is what App Review reads. Haptics cannot fill in — on device
    /// (2026-08-08) iOS withheld every tap under a locked screen. A silent
    /// session therefore stops when the person leaves; `SessionView` says so.
    var playsInBackground: Bool {
        audio != nil
    }

    func prepare() {
        haptics?.prepare()
        audio?.prepare()
    }

    /// Both sides have something in flight to hand back. The sentence is the
    /// obvious one; the swell is the one that was missed for a while, because a
    /// breath is a single continuous haptic event as long as its phase, so a
    /// pause mid-inhale left the phone playing the rest of that inhale out.
    func pause() {
        haptics?.pause()
        audio?.pause()
    }

    /// Only sound resumes. A swell the pause stopped stays stopped until the
    /// next boundary, for the reason `HapticController.pause()` gives.
    func resume() {
        audio?.resume()
    }

    func play(_ beat: SessionTimeline.Beat) {
        haptics?.play(beat)
        audio?.play(beat)
    }

    func playCompletion() {
        haptics?.playCompletion()
        audio?.playCompletion()
    }

    func stop() {
        haptics?.stop()
        audio?.stop()
    }
}
