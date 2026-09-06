import OndKit
import SwiftUI

struct WristCuePreviewView: View {
    @Environment(WatchSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var style = WatchHapticStyle.Preview.current
    @State private var preview: CuePreview?
    @State private var comfortCheck = false
    @State private var runtime = ExtendedRuntime()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Breathe normally. Watch the words to learn each cue.").font(.caption)
                Picker("Pattern", selection: $style) {
                    ForEach(WatchHapticStyle.Preview.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .disabled(preview?.isPlaying == true)
                Toggle("Five-minute check", isOn: $comfortCheck)
                    .disabled(preview?.isPlaying == true)
                Text(preview?.currentBeat?
                    .instruction ?? (preview?.didFinish == true ? "Finished" : "Ready"))
                    .font(.title3)
                Button(preview?.isPlaying == true ? "Stop" : "Try cues") {
                    if preview?.isPlaying == true {
                        preview?.stop()
                    } else {
                        let next = CuePreview(cues: WatchHapticController(
                            settings: settings,
                            preview: style
                        ), comfortCheck: comfortCheck)
                        preview = next
                        runtime.start()
                        next.start()
                    }
                }
                .disabled(!settings.playsHaptics)
                Text(settings.playsHaptics
                    ? "Preview only. Your practice pattern stays the same."
                    : "Turn on Haptics in Settings to try the cues.")
                    .font(.caption2)
                if runtime.state == .unavailable {
                    Text(
                        "The watch could not keep the preview running. Try again while the app is open."
                    )
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Try cues")
        .onDisappear {
            preview?.stop()
            runtime.invalidate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, runtime.state != .running {
                preview?.stop()
            }
        }
        .onChange(of: runtime.state) { _, state in
            if state == .unavailable {
                preview?.stop()
            }
        }
        .onChange(of: preview?.isPlaying) { _, playing in
            if playing == false, runtime.state != .unavailable {
                runtime.invalidate()
            }
        }
    }
}
