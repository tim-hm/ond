import OndKit
import OndUI
import SwiftUI

/// Health write, read, and live-watch preferences as one settings section.
struct HealthSettingsSection: View {
    @Binding private var asksHowYouFeel: Bool
    @Binding private var showsWristPulse: Bool
    @Binding private var coachReadsHealthTrends: Bool
    @Binding private var writesMindfulMinutes: Bool

    /// Whether each paid row still has to name what it needs. Without the
    /// marker the row reads as free until turning it on opens the offer
    /// instead.
    private let wristPulseNeedsPlus: Bool
    private let healthTrendsNeedsPlus: Bool

    let preparePulse: () async -> Void
    let requestReadAccess: () -> Void

    init(
        asksHowYouFeel: Binding<Bool>,
        showsWristPulse: Binding<Bool>,
        coachReadsHealthTrends: Binding<Bool>,
        writesMindfulMinutes: Binding<Bool>,
        wristPulseNeedsPlus: Bool,
        healthTrendsNeedsPlus: Bool,
        preparePulse: @escaping () async -> Void,
        requestReadAccess: @escaping () -> Void
    ) {
        _asksHowYouFeel = asksHowYouFeel
        _showsWristPulse = showsWristPulse
        _coachReadsHealthTrends = coachReadsHealthTrends
        _writesMindfulMinutes = writesMindfulMinutes
        self.wristPulseNeedsPlus = wristPulseNeedsPlus
        self.healthTrendsNeedsPlus = healthTrendsNeedsPlus
        self.preparePulse = preparePulse
        self.requestReadAccess = requestReadAccess
    }

    var body: some View {
        Section {
            Toggle(isOn: $asksHowYouFeel) {
                settingsLabel("Mood before and after", description: nil)
            }
            .accessibilityIdentifier("settings-health-check-ins")

            Toggle(isOn: $showsWristPulse) {
                settingsLabel(
                    "Live heart rate",
                    description: wristPulseNeedsPlus ? SubscriptionTier.plusRequirementNote : nil
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
                    "Heart and sleep data",
                    description: healthTrendsNeedsPlus ? SubscriptionTier.plusRequirementNote : nil
                )
            }
            .accessibilityIdentifier("settings-health-watch-trends")
            // The preference and Health's permission remain separate choices.
            .onChange(of: coachReadsHealthTrends) { _, isOn in
                guard isOn else { return }
                requestReadAccess()
            }

            Toggle(isOn: $writesMindfulMinutes) {
                settingsLabel("Mindful minutes", description: nil)
            }
            .accessibilityIdentifier("settings-health-mindful-minutes")
        } header: {
            Text("Health")
        }
        .listRowBackground(Theme.Surface.raised)
    }
}
