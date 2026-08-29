import OndKit
import OndUI
import SwiftUI

/// Session guidance, breath, sound, and phone haptic preferences.
struct PracticeSettingsSection: View {
    let settings: SessionSettings
    let stacksPickers: Bool
    let reduceMotion: Bool

    var body: some View {
        @Bindable var settings = settings
        let breathVisual: Binding<BreathVisualStyle> = reduceMotion
            ? .constant(settings.breathVisual.drawn(underReduceMotion: reduceMotion))
            : $settings.breathVisual

        Section {
            settingsPicker("Guidance", selection: $settings.guidance, stacks: stacksPickers) {
                ForEach(SessionGuidance.allCases) { level in
                    Text(level.title).tag(level)
                }
            }

            settingsPicker(
                "Breath",
                description: reduceMotion
                    ? "Reduce Motion is on, so the ring sweeps and the core holds still."
                    : nil,
                selection: breathVisual,
                stacks: stacksPickers
            ) {
                ForEach(BreathVisualStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            // Reduce Motion has already selected Sweeping, so the row states
            // the rendering in force and why, not the one still stored behind
            // it and not a choice that could take no effect.
            .disabled(reduceMotion)

            settingsPicker("Cues", selection: $settings.cueMode, stacks: stacksPickers) {
                ForEach(SessionCueMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            settingsPicker("Sound", selection: $settings.sound, stacks: stacksPickers) {
                ForEach(SessionSound.allCases) { sound in
                    Text(sound.title).tag(sound)
                }
            }
            // Audio strength is meaningful only for a cue mode that plays it.
            .disabled(!settings.cueMode.playsAudio)

            settingsPicker(
                "Haptic strength",
                description: settings.cueMode.screenOffNote,
                selection: $settings.hapticStrength,
                stacks: stacksPickers
            ) {
                ForEach(HapticStrength.allCases) { strength in
                    Text(strength.title).tag(strength)
                }
            }
            // A haptic dial under a cueless mode would be connected to nothing.
            .disabled(!settings.cueMode.playsHaptics)
        } header: {
            Text("Practice")
        }
        .listRowBackground(Theme.Surface.raised)
    }
}
