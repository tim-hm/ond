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
                ProtocolsView(
                    routes: routes,
                    catalogue: catalogue,
                    sessions: sessions,
                    journey: journey
                )
            } label: {
                // The protocols only this wrist can deliver — the door the
                // phone's handoff sheet points at. The phone's own Protocols tab
                // carries the same symbol, kept in step by hand.
                Label("Protocols", systemImage: "checklist")
            }

            NavigationLink {
                JourneyView(model: journey)
            } label: {
                // The wrist keeps a Journey screen the phone no longer has a tab
                // for: the phone folded its numbers into Home, which is a
                // scrolling document, and a wrist has no room for one. The
                // signpost is this screen's own symbol now rather than a
                // borrowed one.
                Label("Journey", systemImage: "signpost.right")
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            #if DEBUG
                NavigationLink {
                    HapticSamplerView()
                } label: {
                    Label("Haptic sampler", systemImage: "waveform.path")
                }
            #endif
        }
        .navigationTitle("önd")
    }
}
