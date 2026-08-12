import OndKit
import SwiftUI

/// The one road from a row somebody tapped to a session actually running.
///
/// Three surfaces begin a `DialStop` now — Home's starred rows, its "pick up
/// where you left off" row, and the Protocols list — and every one of them has
/// to answer the same questions in the same order: is this exercise open at this
/// tier, can a phone keep the promise the stop makes, and what does the person
/// see while that is decided. It was one screen's private funnel while home was
/// the only place a stop could be tapped; the rule it enforces did not change
/// when the second and third arrived, so neither did the number of copies of it.
///
/// The lock is checked before the surface, because it applies to both.
/// `SessionStart` is the gate for a full-screen session and says why a second
/// copy of that check is a second place to forget it — but a handoff never
/// reaches it, and the wrist holds no `SubscriptionStore` to gate with. A paid
/// exercise prescribed by an occasion would otherwise be free to anybody with a
/// watch, switched on by a server-side column with no app release anywhere near
/// it.
///
/// A model rather than three `@State`s and a method, so what a tap does is
/// testable in principle and, more immediately, so the three presentations that
/// answer it travel together: `stopLauncher(_:onFinish:)` installs all three,
/// and a screen that adopted the funnel without one of them would silently drop
/// whichever outcome it left out.
@Observable
@MainActor
final class StopLauncher {
    /// The session a tap started. Written back by the cover on dismissal, which
    /// is why it is not `private(set)`.
    var started: StartedSession?

    /// Whether a tap landed on something this tier does not open.
    ///
    /// Which stop is not kept: there is one subscription, and the paywall says
    /// the same thing whichever row was tapped.
    var isShowingPaywall = false

    /// The occasion somebody tapped that only the wrist can deliver, if any.
    /// Held for the sheet's copy — the exchange itself is `wrist`'s.
    var wristbound: DialStop?

    private let sessions: any SessionRecording
    private let settings: SessionSettings
    private let plus: SubscriptionStore
    private let wrist: WristLaunchModel

    /// - Parameters:
    ///   - sessions: where a finished session is recorded.
    ///   - settings: this person's own dials and cue preferences.
    ///   - plus: read at the moment of the tap rather than snapshotted, so a
    ///     subscription bought on the paywall this launcher just opened is in
    ///     force for the next tap without anything having to refresh.
    ///   - wrist: the handoff, for the occasions a phone cannot deliver
    ///     quietly.
    init(
        sessions: any SessionRecording,
        settings: SessionSettings,
        plus: SubscriptionStore,
        wrist: WristLaunchModel
    ) {
        self.sessions = sessions
        self.settings = settings
        self.plus = plus
        self.wrist = wrist
    }

    /// Starts a stop here, or hands it to the wrist, or says why neither can
    /// happen.
    ///
    /// A discreet occasion is the subtler of the three outcomes: the promise the
    /// word makes is one only `OndWatch` can keep — it taps the rhythm out with
    /// nothing on screen — so starting the full-screen session from here would
    /// break it while looking like success. What happens instead is a handoff.
    ///
    /// `stop.dose` is the whole of the length decision — an occasion's
    /// prescription where there is one, this person's own dials otherwise — and
    /// reading it here rather than re-deciding is what keeps the length printed
    /// on the row and the length actually played the same number.
    func begin(_ stop: DialStop) {
        guard stop.technique.isUnlocked(for: plus.tier) else {
            isShowingPaywall = true
            return
        }

        guard stop.surface == .fullScreen else {
            handOff(stop)
            return
        }

        let start = SessionStart(sessions: sessions, settings: settings, tier: plus.tier)

        guard let model = start.session(
            for: stop.technique,
            dialledWith: stop.dose,
            register: stop.register,
            occasionSlug: stop.occasionSlug
        ) else {
            isShowingPaywall = true
            return
        }

        started = StartedSession(model: model)
    }

    /// What the handoff sheet reports, or `.failed` where the guard below
    /// refused to send at all — which the sheet words as the wrist being out of
    /// reach.
    var handoffPhase: WristLaunchModel.Phase {
        wrist.phase ?? .failed
    }

    /// Withdraws an order nobody is waiting for.
    ///
    /// Dismissal is the withdrawal: an order left standing would ride the next
    /// ordinary context out to the watch and start a session somebody closed a
    /// sheet on.
    func dismissHandoff() {
        wrist.dismiss()
    }

    /// Sends a discreet occasion to the wrist and opens the sheet that reports
    /// how it went.
    ///
    /// Only an occasion ever asks for the discreet surface — `DialStop.surface`
    /// answers `.fullScreen` for everything else — so the guard is structural
    /// rather than a case with copy of its own: were a stop to arrive without a
    /// slug, the sheet shows the sentence the phone used to end on anyway.
    private func handOff(_ stop: DialStop) {
        wristbound = stop

        guard let occasionSlug = stop.occasionSlug else { return }
        wrist.launch(occasionSlug: occasionSlug, techniqueSlug: stop.technique.slug)
    }
}

extension View {
    /// Installs the three ways a tapped stop can end: the session, the paywall,
    /// and the sheet that reports a handoff.
    ///
    /// One modifier rather than three per screen, on `paywall(for:isPresented:)`'s
    /// reasoning: the presentations are what make `StopLauncher.begin` visible to
    /// the person who tapped, and a screen that adopted the funnel and forgot one
    /// would swallow that outcome without an error anywhere.
    ///
    /// - Parameter onFinish: run when a full-screen session is dismissed.
    ///   Defaulted to nothing, because only a screen drawing something a session
    ///   changes has anything to do — Home re-reads its history, the Protocols
    ///   list has nothing that moved.
    func stopLauncher(
        _ launcher: StopLauncher,
        onFinish: @escaping () -> Void = {}
    ) -> some View {
        modifier(StopLauncherPresentation(launcher: launcher, onFinish: onFinish))
    }
}

private struct StopLauncherPresentation: ViewModifier {
    let launcher: StopLauncher
    let onFinish: () -> Void

    func body(content: Content) -> some View {
        @Bindable var launcher = launcher

        return content
            .paywall(for: .general, isPresented: $launcher.isShowingPaywall)
            // A sheet rather than an alert, because it has an outcome to report
            // rather than only a refusal: the same occasion, handed to the
            // device that can keep its promise. `wristbound` is what is open;
            // the phase is what it says.
            .sheet(item: $launcher.wristbound) {
                launcher.dismissHandoff()
            } content: { stop in
                WristHandoffSheet(occasionTitle: stop.title, phase: launcher.handoffPhase) {
                    launcher.wristbound = nil
                }
            }
            .fullScreenCover(item: $launcher.started, onDismiss: onFinish) { session in
                SessionView(model: session.model)
            }
    }
}
