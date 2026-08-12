import OndKit
import SwiftUI

/// The screens the chrome shows, built from the composition root's models.
///
/// One builder rather than the expressions inline, so `AppChrome` is about how
/// the roots are presented and this is about what they are made of — the two
/// change for different reasons.
///
/// Isolated because building a view is: every screen here holds a `@MainActor`
/// model, and a nonisolated builder would be constructing them from nowhere in
/// particular.
@MainActor
struct AppRoots {
    let catalogue: TechniqueListModel
    /// The exercises this person wrote. Beside the catalogue rather than folded
    /// into it: two services, two loads, and only one of them needs an identity.
    let own: UserTechniqueModel
    /// The occasions and the Start here progression, which Home and the
    /// Protocols tab both read.
    let routes: RoutesModel
    let sessions: any SessionRecording
    let journey: JourneyModel
    let profiles: ProfileStore
    let foundations: FoundationsModel
    let assistant: any AssistantReading
    let chats: any ConversationStoring

    /// The three a `StopLauncher` needs, threaded through rather than read from
    /// the environment by the screens that build one: a model cannot read the
    /// environment, and a launcher constructed in a view's `init` has to be
    /// handed everything it holds.
    let settings: SessionSettings
    let plus: SubscriptionStore
    let wrist: WristLaunchModel

    var homeRoot: some View {
        HomeView(
            catalogue: catalogue,
            routes: routes,
            sessions: sessions,
            own: own,
            journey: journey,
            profiles: profiles,
            settings: settings,
            plus: plus,
            wrist: wrist
        )
    }

    var protocolsRoot: some View {
        ProtocolListView(
            catalogue: catalogue,
            routes: routes,
            sessions: sessions,
            settings: settings,
            plus: plus,
            wrist: wrist
        )
    }

    var exercisesRoot: some View {
        TechniqueListView(
            model: catalogue,
            own: own,
            sessions: sessions,
            assistant: assistant,
            chats: chats
        )
    }

    var coachRoot: some View {
        CoachRootView(
            assistant: assistant,
            chats: chats,
            catalogue: catalogue,
            sessions: sessions,
            foundations: foundations
        )
    }
}
