import OndKit
import SwiftUI

/// One switch and one dial, and deliberately nothing else.
///
/// Everything else the phone lets somebody set — appearance, guidance level,
/// per-technique dials, reminders — is a decision made sitting down, and the
/// wrist plays whatever was decided there. Haptics are the exception because the
/// answer changes with the room you are in, which is exactly the kind of thing
/// you change from your wrist.
///
/// No About row, no version string: a screen padded out with things that are not
/// settings is worse than a short one.
struct SettingsView: View {
    @Environment(WatchSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Toggle("Haptics", isOn: $settings.playsHaptics)
                .accessibilityHint("Taps at each phase of the breath")

            Picker("Vibration", selection: $settings.hapticStrength) {
                ForEach(HapticStrength.allCases) { strength in
                    Text(strength.title).tag(strength)
                }
            }
            // Dimmed rather than hidden, as on the phone: a strength dial
            // under a switch that plays no haptics is connected to nothing.
            .disabled(!settings.playsHaptics)
        }
        .navigationTitle("Settings")
    }
}
