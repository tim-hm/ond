import OndKit
import SwiftUI

/// The one road from a row somebody tapped to a session actually running.
///
/// Three surfaces begin a `DialStop` — Home's suggestion, its rerun row and its
/// shelf, and the Protocols list — and every one of them has to answer the same
/// questions in the same order: is this exercise open at this tier, can a phone
/// keep the promise the stop makes, what does the person see while that is
/// decided, and what has to be re-read once the session ends. It was one
/// screen's private funnel while Home was the only place a stop could be tapped;
/// the rules did not change when the second and third arrived, so neither did
/// the number of copies of them.
///
/// **This type holds no dependencies and makes no decisions.** It is the
/// presentation state, and a `begin` is a *request* recorded on it;
/// `stopLauncher(_:)` is what resolves one, out of the environment, in the view
/// tree where those objects already live. The round trip is deliberate and is
/// the alternative to threading four install-scoped models through the chrome
/// into every screen's initialiser, where each screen would then hold a second
/// reference to objects its own body already reads from the environment.
///
/// The one thing that cannot come from the environment is where a session is
/// recorded: `SessionRecording` is an existential the composition root hands
/// down as a parameter, and an environment entry for it would need a default —
/// which is to say a silent no-op recorder. So it is the launcher's one stored
/// dependency.
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
    /// Resolves what `StopLauncher.begin` asked for, and installs the three ways
    /// it can end: the session, the paywall, and the sheet that reports a
    /// handoff to the wrist.
    ///
    /// One modifier rather than four things per screen, on
    /// `paywall(for:isPresented:)`'s reasoning: a screen that adopted the funnel
    /// and forgot one of them would swallow that outcome with no error anywhere.
    func stopLauncher(_ launcher: StopLauncher) -> some View {
        modifier(StopLauncherPresentation(launcher: launcher))
    }
}

private struct StopLauncherPresentation: ViewModifier {
    let launcher: StopLauncher

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus
    @Environment(WristLaunchModel.self) private var wrist

    /// Refreshed the moment a session ends, wherever it was begun from.
    ///
    /// Here rather than as a callback each adopting screen passes in, which is
    /// what it was: the Protocols tab took the default and did nothing, so a
    /// session breathed there left Home's practice context and Progress history
    /// stale until the app was relaunched. "A finished session changes what
    /// this person has done" is a fact about the app, not a courtesy one screen
    /// remembers to extend to another.
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
                strength: settings.hapticStrength,
                sound: settings.sound
            )
        }
    }

    /// Sends a discreet protocol to the wrist and opens the sheet that reports
    /// how it went.
    ///
    /// Only a protocol ever asks for the discreet surface — `DialStop.surface`
    /// answers `.fullScreen` for everything else — so the guard is structural
    /// rather than a case with copy of its own: were a stop to arrive without a
    /// slug, the sheet shows the sentence the phone used to end on anyway.
    private func handOff(_ stop: DialStop, as handoff: WristSessionHandoff) {
        launcher.wristbound = stop

        guard let occasionSlug = handoff.occasionSlug else { return }
        wrist.launch(occasionSlug: occasionSlug, techniqueSlug: handoff.techniqueSlug)
    }
}
