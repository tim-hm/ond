import OndKit
import SwiftUI

struct SettingsView: View {
    @Environment(WatchSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var settings = settings

        List {
            Toggle("Haptics", isOn: $settings.playsHaptics)
                .accessibilityHint("Vibrates with each phase of the breath")
            NavigationLink("Try the cues") { WristCuePreviewView() }
            Picker(
                "Breath",
                selection: reduceMotion ? .constant(.sweeping) : $settings.breathVisual
            ) {
                ForEach(BreathVisualStyle.allCases) { style in Text(style.title).tag(style) }
            }
            .disabled(reduceMotion)
            Text(reduceMotion ? "Reduce Motion uses the sweeping guide." :
                "This guide setting applies to this watch.")
                .font(.caption2)
        }
        .navigationTitle("Settings")
    }
}
