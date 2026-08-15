import OndKit
import OndUI
import SwiftUI

/// Session guidance, animation, sound, and phone haptic preferences.
struct PracticeSettingsSection: View {
    let settings: SessionSettings
    let stacksPickers: Bool
    let reduceMotion: Bool

    var body: some View {
        @Bindable var settings = settings

        Section {
            settingsPicker("Guidance", selection: $settings.guidance, stacks: stacksPickers) {
                ForEach(SessionGuidance.allCases) { level in
                    Text(level.title).tag(level)
                }
            }

            settingsPicker(
                "Breath animation", selection: $settings.breathVisual, stacks: stacksPickers
            ) {
                ForEach(BreathVisualStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            // Reduce Motion always draws the ring, so the alternative style
            // would be a control connected to nothing.
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
