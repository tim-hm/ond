import OndKit
import OndUI
import SwiftUI

/// Session guidance, breath, sound, and phone haptic preferences.
struct PracticeSettingsSection: View {
    let settings: SessionSettings
    let stacksPickers: Bool
    let reduceMotion: Bool

    /// Why a row is switched off, said on the row itself. Every row in this
    /// section that can be disabled keeps its label and its value and states
    /// its reason: a control that greys out with nothing said reads as a
    /// fault rather than as a consequence of another choice.
    private static let breathForced =
        "Reduce Motion is on, so the ring sweeps and the core holds still."
    private static let soundOff = "Your cues play no sound, so there is nothing to choose."
    private static let hapticsOff = "Your cues play no haptics, so there is nothing to set."

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
                description: reduceMotion ? Self.breathForced : nil,
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

            settingsPicker(
                "Cues",
                // The consequence sits under the label that decides it. The
                // Haptic strength row carried this until the mode that says
                // the most about a screen going off — the one that plays no
                // haptics — was the mode that switched that row off.
                description: settings.cueMode.screenOffNote,
                selection: $settings.cueMode,
                stacks: stacksPickers
            ) {
                ForEach(SessionCueMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            settingsPicker(
                "Sound",
                description: settings.cueMode.playsAudio ? nil : Self.soundOff,
                selection: $settings.sound,
                stacks: stacksPickers
            ) {
                ForEach(SessionSound.allCases) { sound in
                    Text(sound.title).tag(sound)
                }
            }
            // Audio strength is meaningful only for a cue mode that plays it.
            .disabled(!settings.cueMode.playsAudio)

            settingsPicker(
                "Haptic strength",
                description: settings.cueMode.playsHaptics ? nil : Self.hapticsOff,
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
