import OndKit
import OndStyle
import OndUI
import SwiftUI

struct CuePreviewView: View {
    let settings: SessionSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sound = SessionSoundStyle.current
    @State private var preview: CuePreview?
    @State private var simulatesEngineFailure = false
    @State private var comfortCheck = false

    var body: some View {
        let drawsArc = settings.breathVisual.drawn(underReduceMotion: reduceMotion) == .sweeping
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Try one cycle to learn the cues. You can breathe normally while listening."
                    )
                    Text("This preview is not saved as a practice.")
                        .font(.caption).foregroundStyle(Theme.Ink.secondary)
                    Toggle("Five-minute comfort check", isOn: $comfortCheck)
                        .disabled(preview?.isPlaying == true)
                    if settings.cueMode.playsAudio {
                        Picker("Sound", selection: $sound) {
                            ForEach(SessionSoundStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .disabled(preview?.isPlaying == true)
                        Text(
                            "Sound plays even in Silent Mode and mixes with other audio. Set a comfortable volume first."
                        )
                        .font(.caption)
                    }
                    Text(settings.cueMode.title)
                    if let preview, preview.isPlaying {
                        TimelineView(.animation(
                            minimumInterval: drawsArc ? Theme.Motion.restfulFrameInterval : nil
                        )) { _ in
                            let elapsed = preview.elapsed
                            let beat = preview.timeline.beat(at: elapsed)
                            ZStack {
                                SessionOrb(
                                    beat: beat,
                                    level: drawsArc ? 0.5 : SessionTimeline.Beat
                                        .level(ofFullness: beat?.lungFullness(at: elapsed) ?? 0),
                                    coreTravels: !drawsArc,
                                    hold: beat.map { BreathGlyph.Pose.holdPresence(
                                        near: $0,
                                        in: preview.timeline,
                                        at: elapsed
                                    ) } ?? 0,
                                    extent: 140
                                )
                                if drawsArc {
                                    PhaseArc(
                                        fraction: beat?.fraction(at: elapsed) ?? 0,
                                        tint: beat?.kind.isHold == true ? Theme.Breath
                                            .hold : Theme.Breath.inhale,
                                        lineWidth: 4
                                    )
                                    .frame(width: 125, height: 125)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.close)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
                        .environment(\.colorScheme, .dark)
                    }
                    #if DEBUG
                        if settings.cueMode.playsHaptics {
                            Toggle("Simulate haptic engine failure", isOn: $simulatesEngineFailure)
                                .disabled(preview?.isPlaying == true)
                        }
                    #endif
                    Text(preview?.currentBeat?
                        .instruction ?? (preview?.didFinish == true ? "Finished" : "Ready"))
                        .font(.largeTitle).frame(maxWidth: .infinity, minHeight: 80)
                        .accessibilityAddTraits(.updatesFrequently)
                    Button(preview?.isPlaying == true ? "Stop preview" : "Play preview") {
                        if preview?.isPlaying == true {
                            preview?.stop()
                        } else {
                            let next = CuePreview(cues: SessionCues(
                                mode: settings.cueMode,
                                strength: settings.hapticStrength,
                                sound: sound,
                                simulatesEngineFailure: simulatesEngineFailure
                            ), comfortCheck: comfortCheck)
                            preview = next
                            next.start()
                        }
                    }
                }
            }
            .navigationTitle("Try the cues")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onDisappear { preview?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                preview?.stop()
            }
        }
    }
}
