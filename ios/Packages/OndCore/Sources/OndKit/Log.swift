import os

/// The one subsystem the phone, the watch and this shared package all log under.
///
/// Deriving it from `Bundle.main.bundleIdentifier` names the *host process*, so
/// a file in this package filed under one subsystem when the phone loaded it and
/// another when the watch did — and `log stream --subsystem xyz.holmie.ond`
/// then silently omitted the watch, the target whose failures are hardest to
/// reproduce.
public enum Log {
    /// The stable subsystem shared by every app target and this package.
    public static let subsystem = "xyz.holmie.ond"

    /// Every channel production code currently logs through.
    ///
    /// Keeping the closed set beside the subsystem makes a new category an
    /// intentional vocabulary change. The repository's observability check
    /// compares this set with every category literal in production Swift.
    static let categories: Set<String> = [
        "account",
        "assistant",
        "audio",
        "bolt-store",
        "catalogue-export",
        "chat-store",
        "haptics",
        "health",
        "home",
        "identity",
        "journey-sync",
        "leaderboard",
        "live-activity",
        "profile",
        "reference-cache",
        "resting-rate-store",
        "safety",
        "schedules",
        "session-runtime",
        "session-store",
        "settings",
        "subscription",
        "user-technique",
        "voice-clips",
        "watch-link",
    ]
}

public extension Logger {
    /// A logger on the app's own subsystem, which is the only one worth writing
    /// to — this initialiser exists so that getting it right takes fewer
    /// keystrokes than getting it wrong.
    ///
    /// - Parameter category: the channel, named for what it carries rather than
    ///   for the file it sits in, so both ends of the phone↔watch handoff file
    ///   under `watch-link`. `Log.categories` holds the closed set.
    init(category: String) {
        self.init(subsystem: Log.subsystem, category: category)
    }
}
