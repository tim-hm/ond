import Foundation
import Observation

/// The wrist's preference for whether it taps. The phone keeps
/// `SessionSettings`; this is its own type because that one carries
/// preferences the watch has no screen for. In OndKit because the watch
/// target has no test bundle. The suite is a parameter so a test does not
/// write shared process state the next launch would read.
@MainActor
@Observable
public final class WatchSettings {
    private static let hapticsKey = "session.haptics"

    /// Whether session haptics are felt. Off leaves a visual-only session, which
    /// is the whole point of the switch: the same technique, silently, for a
    /// room or a wrist that should not be tapped.
    public var playsHaptics: Bool {
        didSet { defaults.set(playsHaptics, forKey: Self.hapticsKey) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Assigning in an initialiser does not run `didSet`, which is what
        // keeps this from writing back the value it just read.
        playsHaptics = defaults.flag(forKey: Self.hapticsKey, default: true)
    }
}
