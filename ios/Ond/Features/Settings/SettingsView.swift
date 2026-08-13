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
/// **A named group answers one question, and the label on a row is expected to
/// explain it.** The screen spent a while as nine unlabelled cards whose
/// footers did a header's work — you met the controls first and found out what
/// they were afterwards. The top group goes unheaded on the same argument in
/// reverse: directly under the screen's own title, "Profile" and "Theme"
/// explain themselves, and a header would only restate the word above it. A
/// row that still needs a paragraph is a row that is badly named, so no group
/// carries explanatory text at all. The two footers left in the file report
/// rather than explain: the cue mode's screen-off cost, rewritten as the
/// selection moves, and a sign-in that failed.
///
/// The two pickers that grey themselves out — haptic strength under a cueless
/// mode, the breath guide under Reduce Motion — went unexplained with the rest.
/// Their reasoning stays in the comments beside them, where the person who might
/// undo it will read it; on screen a dimmed control beneath the switch that
/// dimmed it is legible without being narrated.
///
/// Four groups: the everyday dials — the person, their Health switches, the
/// app's look, the reminders — then the practice itself, then who this
/// install is and what it is on, then the small print.
///
/// Health sits beside Profile rather than in a section of its own, and both
/// directions carry a switch on top of Health's own permission sheet, which
/// keeps the last word. Neither switch is a proxy for that sheet: watch trends
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
    /// Only to ask for the grant the wrist switch needs — see the row itself.
    @Environment(PulseMonitor.self) private var pulse
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

                // Dimmed rather than hidden below the subscription, with the
                // offer under it: a switch that vanished with the tier would
                // leave somebody who lapsed unable to find the setting they
                // remember. What it governs is the coach *reading* the trends,
                // which is a briefing on a model call — the write below is free
                // at every tier, because filling in somebody's own Health app
                // costs nobody anything.
                Toggle("Share watch trends", isOn: $health.coachReadsHealthTrends)
                    // Asked for here rather than by the setter, on the wrist
                    // row's terms below: storing the preference and asking
                    // Health for access are two decisions, and onboarding
                    // collects this same switch while deliberately raising no
                    // sheet.
                    .onChange(of: health.coachReadsHealthTrends) { _, isOn in
                        guard isOn else { return }
                        health.requestReadAccess()
                    }
                    .disabled(isLocked(.healthTrends, whileOff: !health.coachReadsHealthTrends))

                UpgradePrompt(
                    reason: "Reading your trends is part of",
                    for: .health
                )

                Toggle("Write Mindful Minutes to Health", isOn: $health.writesMindfulMinutes)

                Picker("Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }

                Picker("Reminders", selection: reminderIntensity) {
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
            }
            .listRowBackground(Theme.Surface.raised)

            Section {
                Picker("Guidance", selection: $settings.guidance) {
                    ForEach(SessionGuidance.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }

                Picker("Breath animation", selection: $settings.breathVisual) {
                    ForEach(BreathVisualStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                // The strength picker's reasoning: under Reduce Motion the guide
                // draws its filling ring whatever this says, and a picker
                // connected to nothing should look like it.
                .disabled(reduceMotion)

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
                        Text(sound.title).tag(sound)
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

                // Never dimmed, and shown whether or not a watch is paired: the
                // label names what it needs, and a row that appeared and vanished
                // with a wrist would be a setting nobody could find twice. With no
                // watch it comes to nothing, silently, which is this feature's
                // contract everywhere — see `PulseMonitor`.
                Toggle("Heart rate from your Apple Watch", isOn: $settings.showsWristPulse)
                    // Asked for here rather than at the first session: honouring
                    // this needs a Health grant, and requesting one shows a system
                    // sheet — which over a countdown that carries on behind it is
                    // the one place this deliberately silent feature spoke, and it
                    // spoke over somebody's first breaths.
                    .onChange(of: settings.showsWristPulse) { _, isOn in
                        guard isOn else { return }
                        Task { await pulse.prepare() }
                    }
                    // Dimmed on the trends switch's terms. The badge is the
                    // phone borrowing the wrist's sensor mid-session, which is
                    // the pairing önd+ sells; breathing on the watch by itself
                    // is untouched by this row and by the subscription.
                    .disabled(isLocked(.watchConnected, whileOff: !settings.showsWristPulse))

                UpgradePrompt(
                    reason: "Your watch and phone working together is part of",
                    for: .watch
                )

                // In Practice rather than up with the Health rows, because what
                // it governs is two screens in a session — the write is what
                // follows from an answer, not what the switch is about.
                Toggle("Ask how you feel before and after", isOn: $settings.asksHowYouFeel)
            } header: {
                Text("Practice")
            } footer: {
                // The cue rows close the group so this lands directly under the
                // picker that decides it, and rewrites as the selection moves —
                // which is why Cues sits below the session dials rather than
                // leading them.
                Text(practiceNote)
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
        .paywall(for: .general, isPresented: $isShowingPaywall)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .navigationTitle("Settings")
    }

    /// What the Practice group reports, which is a cost per channel rather than
    /// an explanation of a control — the distinction this screen's own note draws
    /// about its two footers.
    ///
    /// The wrist sentence is here because nothing else on the screen could carry
    /// it: the switch above turns on a workout session that runs on somebody's
    /// watch for the length of every practice, shows on their watch face, and keeps
    /// its sensor sampling throughout. A label cannot say that, and a person
    /// deciding deserves to know it before their battery tells them.
    private var practiceNote: String {
        guard settings.showsWristPulse else { return settings.cueMode.screenOffNote }

        return settings.cueMode.screenOffNote
            + " While a session runs, your watch keeps a workout session open to read"
            + " your heart — you'll see it on your watch face."
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

    /// Whether a switch below `requirement` should refuse the tap.
    ///
    /// Only in the direction that turns something *on*. A subscription that
    /// lapsed leaves preferences behind it, and a switch disabled outright traps
    /// them: somebody who opted into sharing their watch trends and then stopped
    /// paying could no longer withdraw the opt-in — which is the one direction
    /// that must always be available, since the alternative is an app holding
    /// somebody's consent hostage to a renewal.
    private func isLocked(_ requirement: SubscriptionTier, whileOff isOff: Bool) -> Bool {
        plus.tier < requirement && isOff
    }

    /// "2 active" beside the link — enough to know the feature is in use
    /// without opening it. Disabled schedules deliberately don't count.
    private var scheduleSummary: String {
        let active = schedules.schedules.count(where: \.isEnabled)
        return active == 0 ? "None" : "\(active) active"
    }
}
