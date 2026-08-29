import OndKit
import SwiftUI

/// One switch, and deliberately nothing else. Everything else the phone lets
/// somebody set is a decision made sitting down, and the wrist plays what was
/// decided there; haptics are the exception because the answer changes with
/// the room you are in. No About row, no version string: a screen padded out
/// with things that are not settings is worse than a short one.
struct SettingsView: View {
    @Environment(WatchSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Toggle("Haptics", isOn: $settings.playsHaptics)
                .accessibilityHint("Vibrates with each phase of the breath")
        }
        .navigationTitle("Settings")
    }
}
