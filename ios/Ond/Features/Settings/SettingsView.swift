import OndKit
import OndUI
import StoreKit
import SwiftUI

/// The app's personal, practice, Health, reminder, account and legal settings,
/// pushed from Home's toolbar gear. Health switches sit beneath Health's own
/// permission sheet, which keeps the last word. Paid preferences gate only
/// turning on — off always writes, so a lapsed subscription cannot hold
/// consent hostage. About repeats the paywall's legal pair for App Review.
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
        // Each Health row states what it costs once. The row's switch and the
        // row's marker read the same constant, so one cannot be repriced
        // without the other.
        let wristPulseCosts = SubscriptionTier.watchConnected
        let healthTrendsCosts = SubscriptionTier.healthTrends

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

            PracticeSettingsSection(
                settings: settings,
                stacksPickers: stacksPickers,
                reduceMotion: reduceMotion
            )

            HealthSettingsSection(
                asksHowYouFeel: $settings.asksHowYouFeel,
                showsWristPulse: paidPreference(
                    $settings.showsWristPulse,
                    requiring: wristPulseCosts,
                    presenting: .watch
                ),
                coachReadsHealthTrends: paidPreference(
                    $health.coachReadsHealthTrends,
                    requiring: healthTrendsCosts,
                    presenting: .health
                ),
                writesMindfulMinutes: $health.writesMindfulMinutes,
                wristPulseNeedsPlus: plus.tier < wristPulseCosts,
                healthTrendsNeedsPlus: plus.tier < healthTrendsCosts,
                preparePulse: { await pulse.prepare() },
                requestReadAccess: { health.requestReadAccess() }
            )

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

    /// A preference that opens its offer only when turned on below the
    /// required tier. Off always writes through, so somebody whose
    /// subscription lapsed can withdraw an earlier opt-in. A purchase closes
    /// the offer but leaves the preference off, so buying never doubles as
    /// Health consent.
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

    /// The dial, read live and written through on the turn. A hand-built
    /// binding, because moving the dial also reshapes a schedule — awaited
    /// work a property setter has nowhere to await. The position is read here,
    /// not inside `get`: this runs from `body`, so SwiftUI records the
    /// `ProfileStore.profile` read and a turn of the dial redraws the row.
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
