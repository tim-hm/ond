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

    var homeRoot: some View {
        HomeView(
            catalogue: catalogue,
            routes: routes,
            sessions: sessions,
            own: own,
            journey: journey,
            profiles: profiles
        )
    }

    var protocolsRoot: some View {
        ProtocolListView(catalogue: catalogue, routes: routes, sessions: sessions)
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

    var progressRoot: some View {
        PracticeProgressView(
            model: journey,
            catalogue: catalogue,
            own: own,
            profiles: profiles
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
