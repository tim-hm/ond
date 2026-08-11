import OndKit
import SwiftUI

/// The watch app's front door: four rows and nothing else.
///
/// A menu rather than the catalogue itself, which is what this screen used to
/// be. Opening straight into a carousel meant every launch landed on a decision,
/// and it left the other two surfaces to be found behind a glyph at the edge.
/// One tap to a screen that does one thing is what a watch app is.
struct RootMenuView: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    var body: some View {
        List {
            NavigationLink {
                TechniqueCarouselView(model: catalogue, sessions: sessions, journey: journey)
            } label: {
                Label("Exercises", systemImage: "figure.mind.and.body")
            }

            NavigationLink {
                MomentsView(
                    routes: routes,
                    catalogue: catalogue,
                    sessions: sessions,
                    journey: journey
                )
            } label: {
                // The occasions only this wrist can deliver — the door the
                // phone's "start it from OndWatch" alert points at.
                Label("Moments", systemImage: "sparkles")
            }

            NavigationLink {
                JourneyView(model: journey)
            } label: {
                // The phone's Journey tab icon, so the same door has the same
                // handle on both devices.
                Label("Journey", systemImage: "signpost.right")
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            // This row exists only for as long as discreet mode's device
            // question is open; see `DiscreetSpikeView`.
            #if DEBUG
                NavigationLink {
                    DiscreetSpikeView(catalogue: catalogue)
                } label: {
                    Label("Discreet spike", systemImage: "stopwatch")
                }
            #endif
        }
        .navigationTitle("önd")
    }
}
