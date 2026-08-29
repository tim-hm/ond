import OndUI
import SwiftUI

/// Names the API this build is pointed at, beneath a failure, Debug only.
/// A Debug build on hardware chases the generating Mac's baked Bonjour
/// address, and its failures look exactly like real ones; nothing else in the
/// app records which host a build resolved. `#if DEBUG` wraps the whole body,
/// so a Release build has no branch that could show an address.
struct DebugHostNote: View {
    var body: some View {
        #if DEBUG
            Text(AppConfiguration.apiBaseURLDescription)
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.Ink.secondary)
        #else
            EmptyView()
        #endif
    }
}
