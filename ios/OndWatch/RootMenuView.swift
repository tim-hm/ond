import OndKit
import SwiftUI

/// The watch app's front door: three rows and nothing else.
///
/// A menu rather than the catalogue itself, which is what this screen used to
/// be. Opening straight into a carousel meant every launch landed on a decision,
/// and it left the other two surfaces to be found behind a glyph at the edge.
/// One tap to a screen that does one thing is what a watch app is.
///
/// Protocols before Exercises, which is the phone's order in `AppChrome`
/// (`Home · Protocols · Exercises · Progress · Coach`) with the destinations
/// this wrist does not carry left out. Two devices disagreeing about which of
/// two rows comes first is the kind of thing somebody notices without being
/// able to say why, and the wrist is the device somebody reaches for without
/// looking. Nothing reconciles the two lists — the symbols are already kept in
/// step by hand, and the order now joins them.
struct RootMenuView: View {
    let catalogue: TechniqueListModel
    let routes: RoutesModel
    let sessions: any SessionRecording
    let journey: JourneyModel

    var body: some View {
        List {
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
                // carries the same symbol.
                Label("Protocols", systemImage: "checklist")
            }

            NavigationLink {
                TechniqueCarouselView(model: catalogue, sessions: sessions, journey: journey)
            } label: {
                Label("Exercises", systemImage: "figure.mind.and.body")
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
