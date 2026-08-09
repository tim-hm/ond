import Foundation
import OndKit
import Testing

/// The wrist's one preference, over a suite of its own.
///
/// The rule worth pinning is the one `bool(forKey:)` would silently break:
/// haptics are on until somebody turns them off, and a store that cannot tell an
/// unwritten key from a stored `false` starts every watch app silent.
@MainActor
@Suite("Watch settings")
struct WatchSettingsTests {
    /// A suite nobody has written to, and a name nothing else uses — the shared
    /// default would carry state between these tests and into the next launch.
    private func emptyDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "watch-settings-\(UUID().uuidString)"))
    }

    @Test("Haptics are on before anybody has chosen")
    func defaultsToOn() throws {
        #expect(try WatchSettings(defaults: emptyDefaults()).playsHaptics)
    }

    @Test("Turning them off survives the next launch")
    func remembersBeingTurnedOff() throws {
        let defaults = try emptyDefaults()

        WatchSettings(defaults: defaults).playsHaptics = false

        #expect(WatchSettings(defaults: defaults).playsHaptics == false)
    }

    /// Standard is the reference feel the other strengths are named against,
    /// so it is also what a wrist nobody has tuned should play.
    @Test("Strength starts at standard")
    func defaultsToStandardStrength() throws {
        #expect(try WatchSettings(defaults: emptyDefaults()).hapticStrength == .standard)
    }

    @Test("A chosen strength survives the next launch")
    func remembersTheChosenStrength() throws {
        let defaults = try emptyDefaults()

        WatchSettings(defaults: defaults).hapticStrength = .strong

        #expect(WatchSettings(defaults: defaults).hapticStrength == .strong)
    }
}
