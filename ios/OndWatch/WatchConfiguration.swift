import Foundation
import OndKit

/// Where this build of the watch app points its API. The watch talks to the
/// backend directly rather than proxying through the phone, and reads the
/// URL `mise run ios:gen` bakes into the gitignored Info.plist. Narrower than
/// the phone's `AppConfiguration` by one source: no environment override —
/// a setting that only applies under the debugger is usually not in effect.
enum WatchConfiguration {
    // Where a build points when the baked development URL is absent. Split by
    // configuration as the phone's is: a TestFlight wrist has no route to
    // loopback, while Debug keeps localhost — the watch simulator shares it
    // with the Mac, so 29100 reaches a backend started with `mise run dev`.
    #if DEBUG
        private static let defaultBaseURL = "http://localhost:29100"
    #else
        private static let defaultBaseURL = Deployment.apiBaseURL
    #endif

    /// A `let`, not a computed `var`: it is read once at composition and there
    /// is nothing about it that can change while the app runs.
    static let apiBaseURL: URL = {
        let raw = bakedBaseURL ?? defaultBaseURL

        guard let url = URL(string: raw) else {
            preconditionFailure("OndAPIBaseURL is not a valid URL: \(raw)")
        }

        return url
    }()

    /// Debug-only: a release build must never chase a development Mac, however
    /// the plist it shipped with was produced.
    private static var bakedBaseURL: String? {
        #if DEBUG
            Bundle.main.object(forInfoDictionaryKey: "OndAPIBaseURL") as? String
        #else
            nil
        #endif
    }
}
