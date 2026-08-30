import OndUI
import SwiftUI

/// Health write, read, and live-watch preferences as one settings section.
struct HealthSettingsSection: View {
    @Binding private var asksHowYouFeel: Bool
    @Binding private var showsWristPulse: Bool
    @Binding private var coachReadsHealthTrends: Bool
    @Binding private var writesMindfulMinutes: Bool

    let preparePulse: () async -> Void
    let requestReadAccess: () -> Void

    init(
        asksHowYouFeel: Binding<Bool>,
        showsWristPulse: Binding<Bool>,
        coachReadsHealthTrends: Binding<Bool>,
        writesMindfulMinutes: Binding<Bool>,
        preparePulse: @escaping () async -> Void,
        requestReadAccess: @escaping () -> Void
    ) {
        _asksHowYouFeel = asksHowYouFeel
        _showsWristPulse = showsWristPulse
        _coachReadsHealthTrends = coachReadsHealthTrends
        _writesMindfulMinutes = writesMindfulMinutes
        self.preparePulse = preparePulse
        self.requestReadAccess = requestReadAccess
    }

    var body: some View {
        Section {
            Toggle(isOn: $asksHowYouFeel) {
                settingsLabel(
                    "Ask how you feel before and after",
                    description: "Saves your responses as State of Mind in Apple Health. "
                        + "önd does not read them."
                )
            }
            .accessibilityIdentifier("settings-health-check-ins")

            Toggle(isOn: $showsWristPulse) {
                settingsLabel(
                    "Heart rate from your Apple Watch",
                    description: "Shows your heart rate live during practice. Apple Watch "
                        + "keeps a workout open without storing or sharing readings."
                )
            }
            .accessibilityIdentifier("settings-health-live-heart-rate")
            // Asked here rather than over a session's first countdown.
            .onChange(of: showsWristPulse) { _, isOn in
                guard isOn else { return }
                Task { await preparePulse() }
            }

            Toggle(isOn: $coachReadsHealthTrends) {
                settingsLabel(
                    "Read my heart data",
                    description: "Your coach uses sleeping breathing, resting heart rate and "
                        + "heart-rate variability when needed, and Home draws your heart rate "
                        + "around each session you practise. What it reads is not stored or sent."
                )
            }
            .accessibilityIdentifier("settings-health-watch-trends")
            // The preference and Health's permission remain separate choices.
            .onChange(of: coachReadsHealthTrends) { _, isOn in
                guard isOn else { return }
                requestReadAccess()
            }

            Toggle(isOn: $writesMindfulMinutes) {
                settingsLabel(
                    "Write Mindful Minutes to Health",
                    description: "Records iPhone practices as Mindful Minutes in Apple Health."
                )
            }
            .accessibilityIdentifier("settings-health-mindful-minutes")
        } header: {
            Text("Health")
        }
        .listRowBackground(Theme.Surface.raised)
    }
}
