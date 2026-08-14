import OndKit
import OndUI
import StoreKit
import SwiftUI

/// The app's personal, practice, Health, reminder, account and legal settings.
///
/// Pushed from Home's toolbar gear, so it brings no navigation of its own — the
/// stack it draws its title and its back button in is Home's, which is
/// also what lets `SchedulesView` and `ProfileView` push one deeper from here.
///
/// Each named group answers one question. General is who the app is for and how
/// it looks; Practice is how a session guides; Health is what may cross the app's
/// boundary; Reminders is when it should ask for attention. Account and About
/// then carry identity, billing and the small print. Keeping those concerns in
/// that order gives every preference one predictable home.
///
/// The two pickers that grey themselves out — haptic strength under a cueless
/// mode, the breath guide under Reduce Motion — went unexplained with the rest.
/// Their reasoning stays in the comments beside them, where the person who might
/// undo it will read it; on screen a dimmed control beneath the switch that
/// dimmed it is legible without being narrated.
///
/// The four Health rows are the same four choices onboarding introduces. Their
/// switches are preferences above Health's own permission sheet, which keeps
/// the last word. The two paid preferences stay visible below their tier and
/// open the relevant offer only when somebody tries to turn one on. Turning an
/// existing preference off is never gated, so a lapsed subscription cannot hold
/// consent hostage.
///
/// The two legal links under About repeat the paywall's pair on purpose. App
/// Review expects both reachable outside a purchase flow, and somebody deciding
/// whether to trust the app with their breathing history should not have to open
/// an offer to read what is collected. The version sits with them because the
/// Support ID one section up is half of what a bug report needs.
struct SettingsView: View {
    /// The three Settings routes into the one subscription sheet.
    private enum PresentedPaywall: String, Identifiable {
        /// The Account section's non-feature-specific offer.
        case general
        /// The offer reached from watch trends.
        case health
        /// The offer reached from live wrist heart rate.
        case watch

        var id: Self {
            self
        }

        var context: PaywallContext {
            switch self {
            case .general: .general
            case .health: .health
            case .watch: .watch
            }
        }
    }

    let catalogue: TechniqueListModel

    /// The onboarding answers, to edit, and where the reminder dial's position
    /// is stored. A parameter like `catalogue` rather than an environment value,
    /// because Home already holds the store for its personalised practice cards.
    let profiles: ProfileStore

    /// Schedules live behind a link here rather than a tab: set once, edited
    /// rarely, and the notification tray is their daily face. From the
    /// environment for the reason `settings` is: this screen is two pushes below
    /// a tab root that has no use for the store, and a parameter would make
    /// every view in between carry one.
    @Environment(ScheduleStore.self) private var schedules
    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus
    @Environment(AccountModel.self) private var account
    @Environment(HealthContextModel.self) private var health
    /// Only to ask for the grant the wrist switch needs — see the row itself.
    @Environment(PulseMonitor.self) private var pulse
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var presentedPaywall: PresentedPaywall?
    @State private var isManagingSubscription = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var health = health
        let stacksPickers = dynamicTypeSize.isAccessibilitySize

        List {
            Section {
                NavigationLink("Profile") {
                    ProfileView(profiles: profiles)
                }

                settingsPicker(
                    "Appearance",
                    selection: $settings.appearance,
                    stacks: stacksPickers
                ) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            } header: {
                Text("General")
            }
            .listRowBackground(Theme.Surface.raised)

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

                // One picker rather than a voice-or-tones switch and a second
                // choosing between voices: somebody setting this is answering
                // "what do I hear?" once, and putting the voices behind a toggle
                // would hide the thing they are actually choosing.
                settingsPicker("Sound", selection: $settings.sound, stacks: stacksPickers) {
                    ForEach(SessionSound.allCases) { sound in
                        Text(sound.title).tag(sound)
                    }
                }
                // The strength picker's reasoning below, for the other channel.
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
                // Beside Cues rather than folded into it, and dimmed by it:
                // a strength control under a mode that plays no haptics is
                // a dial connected to nothing.
                .disabled(!settings.cueMode.playsHaptics)
            } header: {
                Text("Practice")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Toggle(isOn: $settings.asksHowYouFeel) {
                    settingsLabel(
                        "Ask how you feel before and after",
                        description: "Saves your responses as State of Mind in Apple Health. "
                            + "önd never sees them."
                    )
                }
                .accessibilityIdentifier("settings-health-check-ins")

                Toggle(
                    isOn: paidPreference(
                        $settings.showsWristPulse,
                        requiring: .watchConnected,
                        presenting: .watch
                    )
                ) {
                    settingsLabel(
                        "Heart rate from your Apple Watch",
                        description: "Shows your heart rate live during practice. Apple Watch "
                            + "keeps a workout open without storing or sharing readings."
                    )
                }
                .accessibilityIdentifier("settings-health-live-heart-rate")
                // Asked here rather than at the first session: honouring this
                // needs a Health grant, and a system sheet over a countdown
                // would interrupt the first breaths it was meant to accompany.
                .onChange(of: settings.showsWristPulse) { _, isOn in
                    guard isOn else { return }
                    Task { await pulse.prepare() }
                }

                Toggle(
                    isOn: paidPreference(
                        $health.coachReadsHealthTrends,
                        requiring: .healthTrends,
                        presenting: .health
                    )
                ) {
                    settingsLabel(
                        "Share watch trends",
                        description: "The coach uses sleeping breathing, resting heart rate, and "
                            + "heart-rate variability when needed."
                    )
                }
                .accessibilityIdentifier("settings-health-watch-trends")
                // Storing the preference and asking Health for access are two
                // decisions. Onboarding stores the same choice while deferring
                // the sheet; a direct turn here asks immediately.
                .onChange(of: health.coachReadsHealthTrends) { _, isOn in
                    guard isOn else { return }
                    health.requestReadAccess()
                }

                Toggle(isOn: $health.writesMindfulMinutes) {
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

            Section {
                settingsPicker("Reminders", selection: reminderIntensity, stacks: stacksPickers) {
                    ForEach(ReminderIntensity.allCases) { intensity in
                        Text(intensity.title).tag(intensity)
                    }
                }

                NavigationLink {
                    SchedulesView(store: schedules, catalogue: catalogue)
                } label: {
                    LabeledContent("Schedules") {
                        Text(scheduleSummary)
                    }
                }
            } header: {
                Text("Reminders")
                    .accessibilityIdentifier("settings-section-reminders")
            }
            .listRowBackground(Theme.Surface.raised)

            AccountSection(
                account: account,
                plus: plus,
                isShowingPaywall: isShowingGeneralPaywall,
                isManagingSubscription: $isManagingSubscription
            )

            Section {
                Link("Privacy", destination: LegalLinks.privacyPolicy)
                Link("Terms", destination: LegalLinks.termsOfUse)
                LabeledContent("Version", value: Self.version)
            } header: {
                Text("About")
            }
            .listRowBackground(Theme.Surface.raised)
        }
        .paletteGround()
        .sheet(item: $presentedPaywall) { paywall in
            PaywallView(paywall.context)
        }
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .navigationTitle("Settings")
    }

    /// The Boolean presentation contract `AccountSection` needs, translated to
    /// the same destination used by the Health rows.
    private var isShowingGeneralPaywall: Binding<Bool> {
        Binding(
            get: { presentedPaywall == .general },
            set: { isPresented in
                if isPresented {
                    presentedPaywall = .general
                } else if presentedPaywall == .general {
                    presentedPaywall = nil
                }
            }
        )
    }

    /// A preference that opens its relevant offer only when the person tries to
    /// turn it on below the required tier.
    ///
    /// The off direction always writes through. That is what lets somebody whose
    /// subscription lapsed withdraw an earlier opt-in. A successful purchase
    /// closes the offer but leaves the preference off until they turn it on
    /// explicitly, so buying never doubles as Health consent.
    private func paidPreference(
        _ preference: Binding<Bool>,
        requiring requirement: SubscriptionTier,
        presenting paywall: PresentedPaywall
    ) -> Binding<Bool> {
        Binding(
            get: { preference.wrappedValue },
            set: { isOn in
                guard isOn, plus.tier < requirement else {
                    preference.wrappedValue = isOn
                    return
                }

                presentedPaywall = paywall
            }
        )
    }

    /// The dial, read live and written through on the turn.
    ///
    /// A hand-built binding rather than `@Bindable`, because the position is
    /// stored on the profile and moving it also reshapes a schedule — work that
    /// has to be awaited, and that a property setter has nowhere to await in.
    ///
    /// The position is read *here* rather than inside `get`, and that is the
    /// load-bearing part: this property is evaluated from `body`, so the read of
    /// `ProfileStore.profile` is the one SwiftUI records, and a turn of the dial
    /// redraws the row. A `get` closure holding the only read would be running
    /// wherever the picker chose to call it, which is not a promise observation
    /// makes.
    private var reminderIntensity: Binding<ReminderIntensity> {
        let dial = ReminderDial(profiles: profiles, schedules: schedules, catalogue: catalogue)
        let current = dial.intensity
        return Binding(
            get: { current },
            set: { intensity in Task { await dial.move(to: intensity) } }
        )
    }

    /// What a bug report quotes, beside the Support ID one section up.
    ///
    /// Read from the bundle rather than written down, for the reason every
    /// derived value in this repo is: a version string maintained by hand is one
    /// that is wrong the first time somebody forgets it.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let release = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(release) (\(build))"
    }

    /// "2 active" beside the link — enough to know the feature is in use
    /// without opening it. Disabled schedules deliberately don't count.
    private var scheduleSummary: String {
        let active = schedules.schedules.count(where: \.isEnabled)
        return active == 0 ? "None" : "\(active) active"
    }
}

/// Keeps the compact system row until an accessibility text size needs the
/// title and selected value to take separate lines.
@ViewBuilder
private func settingsPicker(
    _ title: String,
    description: String? = nil,
    selection: Binding<some Hashable>,
    stacks: Bool,
    @ViewBuilder content: () -> some View
) -> some View {
    if stacks {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            settingsLabel(title, description: description)
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    } else {
        Picker(selection: selection, content: content) {
            settingsLabel(title, description: description)
        }
    }
}

/// A row title and the immediate consequence of changing it.
private func settingsLabel(_ title: String, description: String?) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
        Text(title)
            .foregroundStyle(Theme.Ink.primary)
        if let description {
            Text(description)
                .font(.caption)
                .foregroundStyle(Theme.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
