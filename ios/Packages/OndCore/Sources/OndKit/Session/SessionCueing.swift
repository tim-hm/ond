/// Whatever turns a phase boundary into something you can feel or hear.
/// The implementations live in the app targets: `CHHapticEngine` and
/// `AVAudioPlayer` are iOS-only, and the watch has a different haptic
/// vocabulary. The protocol here keeps the session engine one codebase on
/// both, and lets it run on the host under test with no cues at all.
@MainActor
public protocol SessionCueing {
    /// Whether these cues keep reaching the person with the app backgrounded
    /// and the screen off. This decides whether leaving the app is an
    /// interruption or the posture the technique is done in: a channel that
    /// survives the departure wants the session left running, and one that
    /// goes quiet has to say so, or the person breathes to nothing.
    var playsInBackground: Bool { get }

    /// Called before the first beat. Engine warm-up belongs here, not on the
    /// first boundary, where the latency would land inside the cue.
    func prepare()

    /// Bracket a pause, and the resume that undoes it. The engines stay warm
    /// across these — a resume lands on a phase boundary, and re-warming there
    /// would put the latency inside the cue. What pausing releases is the
    /// claim on background runtime: left playing, a forgotten pause would hold
    /// the phone awake for as long as it lasts.
    func pause()
    func resume()

    func play(_ beat: SessionTimeline.Beat)

    /// The session reached its end, as opposed to being ended.
    func playCompletion()
    func stop()
}
