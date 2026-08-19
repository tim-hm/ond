import OndKit
import OndUI
import SwiftUI

/// The one window: the chrome, what covers it on a first run, what every screen
/// inherits, and the work a launch or a foreground starts.
///
/// Beside `OndApp` for the reason `OndAppComposition` is, and stated there: the
/// root reads as a list of what this install holds and one `init` that fills it
/// in. What that composition is then *for* is this file — and the two answer
/// different questions often enough that reading either meant scrolling past
/// the other.
extension OndApp {
    var body: some Scene {
        WindowGroup {
            // The whole of the chrome is `AppChrome`'s. Reminders live behind a
            // link in Settings; the subscription has no home of its own,
            // opening from whatever was locked.
            AppChrome(
                catalogue: reference.catalogue,
                occasions: reference.occasions,
                sessions: recorder,
                profiles: profiles,
                foundations: reference.foundations,
                assistant: assistant,
                chats: chats,
                router: router
            )
            .fullScreenCover(item: $firstRun) { gate in
                firstRunCover(gate)
            }
            // `brandText`, not `brand`: a tint mostly writes text — every
            // borderless button's label — and `brand` is pinned below its
            // floor.
            .tint(Theme.Accent.brandText)
            // The palette resolves per appearance through the asset catalogue,
            // so one override here re-themes every screen; nil follows the
            // system, which keeps the default behaviour exactly today's.
            .preferredColorScheme(settings.appearance.colorScheme)
            // Outside the first-run presenter so its cover inherits the same
            // dependencies as the app chrome beneath it.
            .environment(settings)
            .environment(warnings)
            .environment(stars)
            .environment(choice)
            .environment(account)
            .environment(plus)
            .environment(schedules)
            .environment(heart)
            .environment(journey)
            .environment(own)
            .environment(wrist)
            .environment(pulse)
            .environment(mood)
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                watch.push()
                Task { await reference.refresh() }
                // Cancelling leaves an entitlement until its paid period ends,
                // and that expiry produces no new purchase for `updates()`.
                if !Self.isUiTesting {
                    Task { await plus.refresh() }
                }
            }
            // A purchase has to reach the wrist without waiting for a relaunch:
            // somebody who subscribes to get the watch working with their phone
            // is, by definition, holding both. The outbox suppresses the push
            // when nothing changed, so this costs a comparison on the rare
            // launches where the tier moves at all.
            .onChange(of: plus.tier) { _, _ in
                watch.push()
            }
            .task { await open() }
            // Its own task because it never returns: the first thing it does is
            // read the entitlement off the device and push anything the server
            // has not acknowledged, and then it listens for renewals and refunds
            // for as long as the app is running. Folded into the task above it
            // would hold the other two open forever.
            .task {
                guard !Self.isUiTesting else { return }
                await plus.watch()
            }
        }
    }

    /// What a first run still owes, as the cover that collects it.
    @ViewBuilder
    private func firstRunCover(_ gate: FirstRunGate) -> some View {
        switch gate {
        case .onboarding:
            if let onboarding {
                OnboardingView(model: onboarding) {
                    firstRun = nil
                    self.onboarding = nil
                }
            }

        case .safety:
            SafetyConsentView(store: consent) {
                // First run's other exit: somebody who quit the flow once their
                // answers were stored and comes back to the terms alone. Their
                // profile may carry a reminder that onboarding's own last step
                // never got to seed, and this is the only other place that ends
                // first run.
                Self.seedReminder(
                    profiles: profiles,
                    schedules: schedules,
                    catalogue: reference.catalogue
                )
                firstRun = nil
            }
        }
    }

    /// The work a launch starts once there is a screen to start it behind.
    private func open() async {
        // A Live Activity outlives the process that requested one, so a session
        // that ended in a crash or a force quit leaves the lock screen still
        // asking somebody to breathe out. Nothing is running at launch, so
        // anything still up is stranded.
        await SessionActivity.clearStranded()

        // Returns early because the fixture *replaces* the sync — see
        // `installIfWanted`. `self.sessions` is qualified because `async let
        // sessions` below shadows the store for the scope.
        #if DEBUG
            if await DemoPractice.installIfWanted(
                sessions: self.sessions,
                scores: scores,
                rates: rates,
                journey: journey
            ) {
                return
            }
        #endif

        async let profile: Void = profiles.syncIfNeeded()
        async let sessions: Void = journey.sync()
        _ = await (profile, sessions)
    }
}
