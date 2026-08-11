import OndKit
import OndUI
import StoreKit
import SwiftUI

/// The app's few dials, plus the reminders, the subscription and the account.
///
/// Pushed from Journey's toolbar gear, so it brings no navigation of its own —
/// the stack it draws its title and its back button in is Journey's, which is
/// also what lets `SchedulesView` and `ProfileView` push one deeper from here.
///
/// **Every section is headed, each header answers one question, and the label on
/// a row is expected to explain it.** The screen spent a while as nine
/// unlabelled cards whose footers did a header's work — you met the controls
/// first and found out what they were afterwards. Naming the groups made that
/// prose redundant, and a row that still needs a paragraph is a row that is
/// badly named, so no section carries explanatory text at all. The two footers
/// left in the file report rather than explain: the cue mode's screen-off
/// cost, rewritten as the selection moves, and a sign-in that failed.
///
/// The two pickers that grey themselves out — haptic strength under a cueless
/// mode, the breath guide under Reduce Motion — went unexplained with the rest.
/// Their reasoning stays in the comments beside them, where the person who might
/// undo it will read it; on screen a dimmed control beneath the switch that
/// dimmed it is legible without being narrated.
///
/// Six sections, one axis at a time: the person and their body, their
/// reminders, a session's cues, its dials — the app's theme among them, one
/// look being a dial rather than an axis of its own — who this install is and
/// what it is on, then the small print.
///
/// Health sits under You rather than in a section of its own, and both
/// directions carry a switch on top of Health's own permission sheet, which
/// keeps the last word. Neither switch is a proxy for that sheet: heart trends
/// are an in-app opt-in because HealthKit never reports a refused read, and
/// the Mindful Minutes write is an in-app opt-out for whoever would rather
/// practise without crediting Health at all. The write spent a while as a
/// stated row on the argument that Health's sheet already governed it; that
/// undersold the person actually deciding, who may want the minutes uncounted
/// even where Health would allow them.
///
/// The two legal links under About repeat the paywall's pair on purpose. App
/// Review expects both reachable outside a purchase flow, and somebody deciding
/// whether to trust the app with their breathing history should not have to open
/// an offer to read what is collected. The version sits with them because the
/// Support ID one section up is half of what a bug report needs.
struct SettingsView: View {
    let catalogue: TechniqueListModel

    /// The onboarding answers, to edit, and where the reminder dial's position
    /// is stored. A parameter like `catalogue` rather than an environment value,
    /// because the screen that pushes this one already holds the store for the
    /// leaderboard card beside the gear.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowingPaywall = false
    @State private var isManagingSubscription = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var health = health

        List {
            Section {
                NavigationLink("Profile") {
                    ProfileView(profiles: profiles)
                }

                Toggle("Share heart trends", isOn: $health.coachReadsHeartTrends)

                Toggle("Write Mindful Minutes to Health", isOn: $health.writesMindfulMinutes)
            } header: {
                Text("You")
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("How often", selection: reminderIntensity) {
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
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Cues", selection: $settings.cueMode) {
                    ForEach(SessionCueMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                // One picker rather than a voice-or-tones switch and a second
                // choosing between voices: somebody setting this is answering
                // "what do I hear?" once, and putting the voices behind a toggle
                // would hide the thing they are actually choosing.
                Picker("Sound", selection: $settings.sound) {
                    ForEach(SessionSound.allCases) { sound in
                        if let voice = sound.voice {
                            Text("\(voice.title) — \(voice.dialect)").tag(sound)
                        } else {
                            Text(sound.title).tag(sound)
                        }
                    }
                }
                // The strength picker's reasoning below, for the other channel.
                .disabled(!settings.cueMode.playsAudio)

                Picker("Haptic strength", selection: $settings.hapticStrength) {
                    ForEach(HapticStrength.allCases) { strength in
                        Text(strength.title).tag(strength)
                    }
                }
                // Beside Cues rather than folded into it, and dimmed by it:
                // a strength control under a mode that plays no haptics is
                // a dial connected to nothing.
                .disabled(!settings.cueMode.playsHaptics)
            } header: {
                Text("Cues")
            } footer: {
                // Its own section so this lands directly under the picker that
                // decides it and rewrites as the selection moves. Folded in with
                // Guidance and Breath guide it would sit two rows below what it
                // describes and read as being about all four.
                Text(settings.cueMode.screenOffNote)
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Guidance", selection: $settings.guidance) {
                    ForEach(SessionGuidance.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }

                Picker("Breath guide", selection: $settings.breathVisual) {
                    ForEach(BreathVisualStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                // The strength picker's reasoning: under Reduce Motion the guide
                // draws its filling ring whatever this says, and a picker
                // connected to nothing should look like it.
                .disabled(reduceMotion)

                Picker("Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            } header: {
                Text("Sessions")
            }
            .listRowBackground(Theme.Surface.raised)

            AccountSection(
                account: account,
                plus: plus,
                isShowingPaywall: $isShowingPaywall,
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
        .paywall(highlighting: offeredTier, isPresented: $isShowingPaywall)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .navigationTitle("Settings")
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

    /// The rung above the current one, which is what the paywall should lead
    /// with — the sheet is a ladder, and the interesting question from here is
    /// always the next step up. Derived from the ladder rather than written out
    /// beside it, like every other tier comparison. A subscriber on the top
    /// rung has nothing above, so their sheet opens on what they already hold,
    /// which reads as confirmation.
    private var offeredTier: SubscriptionTier {
        SubscriptionTier.purchasable.first { $0 > plus.tier } ?? plus.tier
    }

    /// "2 active" beside the link — enough to know the feature is in use
    /// without opening it. Disabled schedules deliberately don't count.
    private var scheduleSummary: String {
        let active = schedules.schedules.count(where: \.isEnabled)
        return active == 0 ? "None" : "\(active) active"
    }
}
