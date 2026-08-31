import Foundation

/// How long a reference model trusts what it holds before the next screen that
/// asks re-checks the server. The second trigger, not the first: the phone
/// refreshes all three models on every foreground, ignoring this window; the
/// wrist has no such hook, so there this does the work. Marked on asking, not on
/// succeeding — it bounds asking, not retrying. A relaunch resets it, deliberately.
struct ReferenceFreshness {
    /// What every reference model uses unless a test says otherwise.
    static let standard: Duration = .seconds(60 * 60)

    private let window: Duration
    private var askedAt: ContinuousClock.Instant?

    /// - Parameter window: how long an answer stays fresh. Injected so a test
    ///   can say "always stale" or "never stale" without sleeping through an
    ///   hour, which is the only thing a clock seam here would buy.
    init(window: Duration = ReferenceFreshness.standard) {
        self.window = window
    }

    /// Whether enough time has passed to be worth asking again. True before the
    /// first ask, which is what makes a model's opening load unconditional.
    var isStale: Bool {
        guard let askedAt else { return true }
        // Continuous rather than suspending, so an hour spent with the phone in
        // a pocket counts as the hour it was.
        return ContinuousClock().now - askedAt >= window
    }

    mutating func markAsked() {
        askedAt = ContinuousClock().now
    }
}
