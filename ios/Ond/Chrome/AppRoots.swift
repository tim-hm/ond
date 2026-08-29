import OndKit
import SwiftUI

/// The screens the chrome shows, built from the composition root's models.
/// One builder so `AppChrome` stays about presentation and this about
/// composition — the two change for different reasons. `@MainActor` because
/// every screen here holds a `@MainActor` model.
@MainActor
struct AppRoots {
    let catalogue: TechniqueListModel
    /// The exercises this person wrote. Beside the catalogue rather than folded
    /// into it: two services, two loads, and only one of them needs an identity.
    let own: UserTechniqueModel
    /// The occasions and the Start here progression. The Protocols tab reads
    /// them; Home only warms the load, because it is the tab every launch
    /// lands on.
    let occasions: OccasionCatalogueModel
    let sessions: any SessionRecording
    let journey: JourneyModel
    let profiles: ProfileStore
    let foundations: FoundationsModel
    let assistant: any AssistantReading
    let chats: any ConversationStoring

    /// What Home's "All exercises" row does — the chrome's tab selection,
    /// reached the only way a leaf under one tab can move another.
    let openExercises: () -> Void

    var homeRoot: some View {
        HomeView(
            catalogue: catalogue,
            occasions: occasions,
            sessions: sessions,
            own: own,
            journey: journey,
            profiles: profiles,
            openExercises: openExercises
        )
    }

    var protocolsRoot: some View {
        ProtocolListView(catalogue: catalogue, occasions: occasions, sessions: sessions)
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
