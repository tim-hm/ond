import AppIntents
import OndKit

/// Pause, from the lock screen. `LiveActivityIntent` runs these in the app's
/// process, where the session is. The directory compiles into the app and the
/// extension both; the system matches the copies by identifier. They stay out
/// of OndKit (iOS 26 breaks package intents on device) and stay `public`
/// (non-public types fail resolution). Undiscoverable: useless with no session.
public struct PauseSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Pause session"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await SessionActivity.pauseRunningSession()
        return .result()
    }
}

/// Resume, from the lock screen.
public struct ResumeSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Resume session"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await SessionActivity.resumeRunningSession()
        return .result()
    }
}

/// "I'm ready" — the end of a retention, from the lock screen.
public struct ReleaseHoldIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "End the hold"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await SessionActivity.releaseRunningHold()
        return .result()
    }
}

/// End, from the lock screen. What was finished is still recorded.
public struct EndSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "End session"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await SessionActivity.endRunningSession()
        return .result()
    }
}
