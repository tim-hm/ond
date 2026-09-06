import Foundation
import Observation

@MainActor
@Observable
public final class CuePreview {
    public private(set) var currentBeat: SessionTimeline.Beat?
    public private(set) var isPlaying = false
    public private(set) var didFinish = false
    public let timeline: SessionTimeline
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let cues: any SessionCueing
    @ObservationIgnored private var began: ContinuousClock.Instant?

    public init(
        cues: any SessionCueing,
        timeline: SessionTimeline? = nil,
        comfortCheck: Bool = false
    ) {
        self.cues = cues
        self.timeline = timeline ?? Self.sample(cycles: comfortCheck ? 27 : 1)
    }

    public var elapsed: Duration {
        guard let began else { return .zero }
        return min(timeline.totalDuration, began.duration(to: ContinuousClock().now))
    }

    public func start() {
        stop()
        didFinish = false
        isPlaying = true
        cues.prepare()
        let began = ContinuousClock().now
        self.began = began
        task = Task { [weak self] in
            guard let self else { return }
            for beat in timeline.beats {
                guard !Task.isCancelled else { return }
                currentBeat = beat
                cues.play(beat)
                do { try await ContinuousClock().sleep(until: began.advanced(by: beat.end))
                } catch {
                    return
                }
            }
            currentBeat = nil
            didFinish = true
            cues.playCompletion()
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            cues.stop()
            isPlaying = false
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        if isPlaying {
            cues.stop()
        }
        isPlaying = false
        currentBeat = nil
        began = nil
    }

    private static func sample(cycles: Int) -> SessionTimeline {
        SessionTimeline(stages: [Stage(phases: [
            Phase(kind: .inhale, duration: .seconds(3)),
            Phase(kind: .holdIn, duration: .seconds(2)),
            Phase(kind: .exhale, duration: .seconds(4)),
            Phase(kind: .holdOut, duration: .seconds(2)),
        ], cycles: cycles)], rounds: 1)
    }
}
