import OndKit
import SwiftUI

/// The one road from a tapped row to a session running: every surface that
/// begins a `DialStop` answers the same questions in the same order, in one
/// copy. It holds no dependencies and decides nothing — `begin` records a
/// request; `stopLauncher(_:)` resolves it from the environment. Only
/// `SessionRecording` is stored: an environment default is a silent no-op recorder.
@Observable
@MainActor
final class StopLauncher {
    /// The stop a row just asked for, until the modifier has resolved it.
    ///
    /// Cleared as soon as it is read, so pressing the same row twice is two
    /// requests rather than one change the second tap cannot express.
    var requested: DialStop?

    /// The session a tap started. Written back by the cover on dismissal, which
    /// is why it is not `private(set)`.
    var started: PhoneSessionLaunch?

    /// Whether a tap landed on something this tier does not open.
    ///
    /// Which stop is not kept: there is one subscription, and the paywall says
    /// the same thing whichever row was tapped.
    var isShowingPaywall = false

    /// The protocol somebody tapped that only the wrist can deliver, if any.
    /// Held for the sheet's copy — the exchange itself is `WristLaunchModel`'s.
    var wristbound: DialStop?

    let sessions: any SessionRecording

    init(sessions: any SessionRecording) {
        self.sessions = sessions
    }

    /// Asks for this stop to be started.
    func begin(_ stop: DialStop) {
        requested = stop
    }
}

extension View {
    /// Resolves what `StopLauncher.begin` asked for, and installs the three
    /// ways it can end: the session, the paywall, and the wrist-handoff sheet.
    /// One modifier, on `paywall(for:isPresented:)`'s reasoning: a screen that
    /// adopted the funnel and forgot one would swallow that outcome silently.
    func stopLauncher(_ launcher: StopLauncher) -> some View {
        modifier(StopLauncherPresentation(launcher: launcher))
    }
}

private struct StopLauncherPresentation: ViewModifier {
    let launcher: StopLauncher

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus
    @Environment(WristLaunchModel.self) private var wrist

    /// Refreshed the moment a session ends, wherever it was begun from. Here
    /// rather than a callback each screen passes in: the Moments tab took
    /// the default and did nothing, so a session breathed there left Home and
    /// Progress stale until relaunch. A finished session changes what this
    /// person has done — a fact about the app, not one screen's courtesy.
    @Environment(JourneyModel.self) private var journey

    func body(content: Content) -> some View {
        @Bindable var launcher = launcher

        return content
            .onChange(of: launcher.requested) { _, requested in
                guard let requested else { return }
                launcher.requested = nil
                begin(requested)
            }
            .paywall(for: .general, isPresented: $launcher.isShowingPaywall)
            // A sheet rather than an alert, because it has an outcome to report
            // rather than only a refusal: the same protocol, handed to the
            // device that can keep its promise. `wristbound` is what is open;
            // the phase is what it says.
            .sheet(item: $launcher.wristbound) {
                // Dismissal is the withdrawal: an order nobody is waiting for
                // must not ride the next ordinary context out to the watch.
                wrist.dismiss()
            } content: { stop in
                WristHandoffSheet(
                    occasionTitle: stop.title,
                    // Nil only where `begin` refused to send at all, which the
                    // sheet words as the wrist being out of reach.
                    phase: wrist.phase ?? .failed
                ) {
                    launcher.wristbound = nil
                }
            }
            .fullScreenCover(item: $launcher.started) {
                Task { await journey.refresh() }
            } content: { session in
                SessionView(model: session.model)
            }
    }

    /// Presents the domain outcome for a requested stop.
    ///
    /// Entitlement, surface, dose and provenance are resolved together in
    /// OndKit; this modifier owns only the SwiftUI state and the wrist exchange.
    private func begin(_ stop: DialStop) {
        switch resolver.resolve(stop, for: plus.tier) {
        case let .phoneSession(session):
            launcher.started = session
        case .subscriptionRequired:
            launcher.isShowingPaywall = true
        case let .wristHandoff(handoff):
            handOff(stop, as: handoff)
        }
    }

    private var resolver: SessionLaunchResolver {
        SessionLaunchResolver(sessions: launcher.sessions) {
            SessionCues(
                mode: settings.cueMode,
                strength: settings.hapticStrength
            )
        }
    }

    /// Sends a discreet protocol to the wrist and opens the sheet that reports
    /// how it went. Only a protocol asks for the discreet surface —
    /// `DialStop.surface` answers `.fullScreen` for everything else — so the
    /// guard is structural: a stop without a slug gets the old ending sentence.
    private func handOff(_ stop: DialStop, as handoff: WristSessionHandoff) {
        launcher.wristbound = stop

        guard let occasionSlug = handoff.occasionSlug else { return }
        wrist.launch(occasionSlug: occasionSlug, techniqueSlug: handoff.techniqueSlug)
    }
}
