import AppIntents
import OndKit

/// Pause, from the lock screen.
///
/// The four intents in this file are the controls on the Live Activity, and
/// they are four types rather than one with a parameter because that is what
/// `Button(intent:)` reads well as at the call site — and because an
/// `AppEnum`'s display metadata would be ceremony for a value nobody ever
/// sees. `LiveActivityIntent` is what runs them in the *app's* process, which
/// is where the session is; an ordinary `AppIntent` would run in the widget
/// extension and reach nothing.
///
/// This directory is compiled into the app target as well as this extension —
/// the `Ond` target names `OndActivity/Intents` in project.yml, the
/// extension's glob covers it already, and so an intent added here is in both
/// targets by construction. That duplication is Apple's own pattern for Live
/// Activity controls: the extension needs the types to draw the buttons, the
/// app needs them to perform, and the system matches the two copies by intent
/// identifier. The tidier arrangement — defining them once in OndKit and
/// registering them through `AppIntentsPackage` — produces identical metadata
/// and buttons that do nothing when pressed on a device (iOS 26 mishandles
/// intents that live in a package), which is why the intents live here and not
/// in the package with the `SessionActivity` surface they drive. `public` is
/// kept for the same reason although no module boundary asks for it: intent
/// resolution has failed in the field for non-public types, and invisible to
/// the metadata index is exactly the failure this file exists to avoid.
///
/// None of them is discoverable. They are meaningless without a session
/// already running, and a Shortcuts action called "Pause" that silently does
/// nothing most of the time is worse than no action at all.
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
