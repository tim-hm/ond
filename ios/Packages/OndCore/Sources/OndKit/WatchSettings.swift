import Foundation
import Observation

/// The wrist's preferences: whether it taps, and how hard. The phone has no
/// business reading them — it keeps `SessionSettings` — and they live here only
/// because the watch target has no test bundle, so a preference with a default
/// is otherwise unpinnable.
///
/// Its own type rather than `SessionSettings`, which was checked first and does
/// not drop in: that one carries an appearance override, a guidance level, the
/// home wheel's last goal, and every technique the person has dialled — none of
/// which the watch has a screen for — and its `SessionCueMode` third case is
/// audio the wrist does not play. A settings screen offering two haptic
/// controls should not drag four unreachable preferences behind it.
///
/// `UserDefaults` for the same reason the phone's is: this is a preference, not
/// history, and it belongs to the device it was set on. The suite is a parameter
/// so a test can hand it one of its own — the default is shared process state,
/// and a test that wrote to it would change what the next launch reads.
@MainActor
@Observable
public final class WatchSettings {
    private static let hapticsKey = "session.haptics"
    private static let strengthKey = "session.hapticStrength"

    /// Whether phase boundaries are felt. Off leaves a visual-only session,
    /// which is the whole point of the switch: the same technique, silently,
    /// for a room or a wrist that should not be tapped.
    public var playsHaptics: Bool {
        didSet { defaults.set(playsHaptics, forKey: Self.hapticsKey) }
    }

    /// How much the wrist says when it taps. The selector is the phone's
    /// `HapticStrength`; what it means here is `WatchHapticStyle`'s to decide,
    /// because `WKHapticType` has no amplitude to scale.
    public var hapticStrength: HapticStrength {
        didSet { defaults.set(hapticStrength.rawValue, forKey: Self.strengthKey) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` rather than `bool(forKey:)`, which cannot tell a
        // key nobody has written from a stored false — and the default is on.
        // Assigning in an initialiser does not run `didSet`, which is what
        // keeps this from writing back the value it just read.
        playsHaptics = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        hapticStrength = defaults.string(forKey: Self.strengthKey)
            .flatMap(HapticStrength.init(rawValue:)) ?? .standard
    }
}
