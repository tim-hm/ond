import OndKit
import OndUI
import SwiftUI

/// The app's chrome, and the only thing `OndApp` puts on screen: five
/// destinations in the system tab bar.
///
/// Settings is left out on purpose: a tab bar is for content sections and
/// settings is not content. It is a gear in Home's toolbar, where somebody
/// starts before changing how the app behaves.
///
/// Coach is a tab rather than the bottom accessory it was first built as. The
/// accessory is a floating shelf in its own glass container — right for a
/// transport control that outlives the screen under it, wrong for a destination,
/// which is what a conversation you navigate to actually is. It carries both
/// rooms — the chat once `SubscriptionTier.assistant` is held, the offer until
/// then, and the basics either way — a door in the same row as the others
/// rather than a thing hovering beside them.
///
/// Nothing here tints anything: the chrome wears the accent `OndApp` sets, on
/// every tab. The bar once took the colour of whatever aim the old board was
/// dialled to — a bar that cross-faded on every detent was the busiest thing
/// left on a screen whose argument is stillness.
struct AppChrome: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording
    let profiles: ProfileStore
    let foundations: FoundationsModel

    /// The one assistant composition, from the root — see `OndApp.assistant`.
    let assistant: any AssistantReading

    /// The coach conversations, threaded through to the Coach tab's list.
    let chats: any ConversationStoring

    /// What a tapped notification asked for. Followed here rather than by any
    /// one tab, because the exercise a reminder names has nothing to do with
    /// where the person happened to leave the app.
    let router: NotificationRouter

    /// The five destinations, as a value the bar can be asked about.
    ///
    /// Named rather than left implicit because the selection is what a deep link
    /// would move, and a `TabView` without one cannot be asked which tab is
    /// showing.
    private enum Destination: Hashable {
        case home
        case protocols
        case exercises
        case progress
        case coach
    }

    /// Which tab is showing. Home on launch, which is where the bar opens.
    @State private var destination: Destination = .home

    /// The session a notification opened, waiting on Begin. Presented over the
    /// bar rather than pushed into a tab: it is a full-screen cover from every
    /// other way in too, and the tab underneath is whatever was last used.
    @State private var invited: PhoneSessionLaunch?

    /// Whether a reminder named an exercise this tier does not open. The
    /// technique itself is not kept: the paywall sells one subscription and says
    /// the same thing whichever exercise was tapped, so holding it would be
    /// presentation state nothing reads.
    @State private var isShowingPaywall = false

    /// The two models the coach's cards write into, read here rather than
    /// handed down: both are already in the environment for the chat four views
    /// below, and a second route to the same object is one that can go stale.
    @Environment(UserTechniqueModel.self) private var own
    @Environment(JourneyModel.self) private var journey

    @Environment(SessionSettings.self) private var settings
    @Environment(SubscriptionStore.self) private var plus

    var body: some View {
        // Built once rather than per `Tab`: the property is a fresh struct each
        // time it is read, and the five closures below would each construct
        // their own on every invalidating pass.
        let roots = roots

        // Exercises and Protocols carry the same symbols as the watch's root
        // menu (`OndWatch/RootMenuView.swift`), kept in step by hand — nothing
        // reconciles the two sets of literals, so retuning one retunes both.
        return TabView(selection: $destination) {
            Tab("Home", systemImage: "house", value: Destination.home) {
                roots.homeRoot
            }

            Tab("Protocols", systemImage: "checklist", value: Destination.protocols) {
                roots.protocolsRoot
            }

            Tab("Exercises", systemImage: "figure.mind.and.body", value: Destination.exercises) {
                roots.exercisesRoot
            }

            Tab("Progress", systemImage: "chart.bar.xaxis", value: Destination.progress) {
                roots.progressRoot
            }

            // A speech bubble: the tab leads with the conversation.
            // CoachRootView's offer and empty states and the exercise screen's
            // coach door carry the same glyph, kept in step by hand.
            Tab("Coach", systemImage: "bubble.middle.bottom", value: Destination.coach) {
                roots.coachRoot
            }
        }
        // Flat, where it used to be off on the one tab that could not scroll.
        // Every root is a document now, and a behaviour scoped to a destination
        // is a rule the next tab has to be told about.
        .tabBarMinimizeBehavior(.onScrollDown)
        .background(Theme.Surface.ground.ignoresSafeArea())
        .fullScreenCover(item: $invited) { session in
            SessionView(model: session.model, entering: .waiting)
        }
        .paywall(for: .general, isPresented: $isShowingPaywall)
        .task { presentPaywallForUiTesting() }
        // Keyed on the request rather than run once, so a tap while the app is
        // already open takes the same road as the tap that launched it.
        .task(id: router.pending) { await follow() }
    }

    /// Gives the UI harness a deterministic route that does not depend on the
    /// simulator's cached StoreKit receipt. Setting the state after the view is
    /// mounted also gives SwiftUI a presentation host for the sheet.
    private func presentPaywallForUiTesting() {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-paywall") {
                isShowingPaywall = true
            }
        #endif
    }

    /// Opens whatever a tapped notification asked for.
    ///
    /// The await is what a cold launch needs: the tap that started the app is
    /// already waiting on the router by the time this first runs, and the
    /// catalogue its slug resolves against is not. Taken unconditionally once
    /// that wait is over — a request that resolves to nothing is dropped rather
    /// than retried, because opening where the app always would is the stated
    /// answer for an exercise the catalogue no longer has.
    private func follow() async {
        guard router.pending != nil else { return }
        await catalogue.loadIfNeeded()

        guard let payload = router.take(),
              case let .loaded(techniques) = catalogue.state,
              let destination = NotificationDestination(
                  payload, in: techniques, tier: plus.tier
              )
        else { return }

        switch destination {
        case let .session(technique):
            let outcome = resolver.resolvePhoneSession(
                technique,
                dialledWith: settings.overrides(for: technique),
                register: .plain,
                occasionSlug: nil,
                for: plus.tier
            )
            switch outcome {
            case let .phoneSession(session):
                invited = session
            case .subscriptionRequired:
                isShowingPaywall = true
            case .wristHandoff:
                break
            }

        case .offer:
            isShowingPaywall = true
        }
    }

    private var resolver: SessionLaunchResolver {
        SessionLaunchResolver(sessions: sessions) {
            SessionCues(
                mode: settings.cueMode,
                strength: settings.hapticStrength,
                sound: settings.sound
            )
        }
    }

    private var roots: AppRoots {
        AppRoots(
            catalogue: catalogue,
            own: own,
            routes: routes,
            sessions: sessions,
            journey: journey,
            profiles: profiles,
            foundations: foundations,
            assistant: assistant,
            chats: chats
        )
    }
}
