import OndUI
import SwiftUI

/// Names the API this build is pointed at, beneath a failure, and only in Debug.
///
/// A Debug build on hardware talks to the generating Mac's Bonjour address,
/// baked into the Info.plist by `mise run ios:gen` — see `AppConfiguration`. It
/// stops answering whenever that Mac's backend is stopped, the phone leaves the
/// Wi-Fi, or the hostname changes, and the failure that follows is
/// indistinguishable from a real one. Nothing else in the app records which host
/// a build resolved, so this is the only place it can be read from.
///
/// `#if DEBUG` around the whole body rather than around a modifier: a Release
/// build compiles the `EmptyView` arm and has no branch to take, so a shipped
/// app cannot show an address however it was launched.
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
