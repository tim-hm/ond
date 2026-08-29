import Foundation
import OndKit

/// The API base URL: `OND_API_BASE_URL`, then the URL `ios:gen` bakes into
/// the Info.plist, then the build-configuration default. The variable exists
/// only under Xcode's debugger, so a device build reads the baked URL. Both
/// overrides compile away in Release; a shipped build gets the default.
enum AppConfiguration {
    // Release points at the deployed API: a TestFlight phone cannot reach the
    // developer's loopback. Debug keeps localhost, where 18100 is the port
    // `crates/api` binds and the simulator shares the Mac's loopback.
    #if DEBUG
        private static let defaultBaseURL = "http://localhost:18100"
    #else
        private static let defaultBaseURL = Deployment.apiBaseURL
    #endif

    /// Traps on an unparseable override: silently falling back to localhost
    /// gives an app that works against the wrong backend, which is harder to
    /// notice than a crash naming the value. A `let`, not a computed `var` —
    /// each read of the environment snapshots it into a fresh dictionary.
    static let apiBaseURL: URL = {
        let raw = ProcessInfo.processInfo.environment["OND_API_BASE_URL"]
            ?? bakedBaseURL
            ?? defaultBaseURL

        guard let url = URL(string: raw) else {
            preconditionFailure("OND_API_BASE_URL is not a valid URL: \(raw)")
        }

        return url
    }()

    /// Host and port for the Debug-only failure note and the boot log line —
    /// the parts of the URL that actually differ between two builds.
    static var apiBaseURLDescription: String {
        guard let host = apiBaseURL.host() else { return apiBaseURL.absoluteString }
        guard let port = apiBaseURL.port else { return host }
        return "\(host):\(port)"
    }

    /// The generating Mac's Bonjour address, written into the gitignored
    /// Info.plist by `mise run ios:gen`. A device build launched from the home
    /// screen has no environment; this is how it finds the dev backend.
    /// Debug-only: a release build must never chase a development Mac.
    private static var bakedBaseURL: String? {
        #if DEBUG
            Bundle.main.object(forInfoDictionaryKey: "OndAPIBaseURL") as? String
        #else
            nil
        #endif
    }
}
