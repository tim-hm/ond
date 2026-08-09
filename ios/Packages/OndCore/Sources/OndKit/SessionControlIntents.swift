#if os(iOS)
    import AppIntents

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

    /// Makes this package's intents visible to the app that links it.
    ///
    /// App Intents are discovered per target at build time, so intents compiled
    /// into a package are not in the app's own metadata — and the lock screen's
    /// buttons are resolved against the *app's* metadata, not the widget's. This
    /// is Apple's declared mechanism for closing that gap; the app names it from
    /// its own `AppIntentsPackage`. Without it the buttons draw correctly and do
    /// nothing when pressed.
    public struct OndKitIntents: AppIntentsPackage {}
#endif
