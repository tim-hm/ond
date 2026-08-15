import Foundation

/// How long a reference model trusts what it is already holding before the next
/// screen that asks for it checks the server again.
///
/// The three reference models each publish local data and refresh behind it,
/// which answered "load on launch" but not "notice that the catalogue changed".
/// Once a model reached `.loaded` nothing asked again for the life of the
/// process. This is the clock that ends that.
///
/// **It is the second trigger, not the first.** The phone already refreshes all
/// three models on every foreground — `OndApp`'s `onChange(of: scenePhase)`
/// calls `Reference.refresh()`, which ignores this window entirely. So on the
/// phone this only bites where a process stays foregrounded past the window and
/// the person then reaches a tab they had not opened yet. The wrist has no such
/// hook, and its screens are pushed rather than kept alive, so there this is the
/// trigger that does the work. Anybody making the app notice a deployment sooner
/// should reach for the foreground hook first; this is the backstop behind it.
///
/// The window is chosen against the cost of being wrong rather than against a
/// rate of change: reference data moves when a deployment moves it, which is to
/// say rarely and never in response to anything the person did. An hour is
/// short enough that somebody who leaves the app open all evening is breathing
/// what was deployed at teatime, and long enough that walking between screens
/// makes one request rather than dozens.
///
/// **Marked on asking, not on succeeding.** A device out of range is exactly
/// where an unbounded retry costs most, and the window's job is to bound how
/// often the app asks. A relaunch resets it, and an explicit `refresh()` — what
/// the foreground hook and pull-to-refresh both call — ignores it entirely, so
/// neither path leaves somebody stuck with an hour-old failure they can see.
///
/// Not persisted, for the same reason: a relaunch is itself the strongest
/// signal that a check is worth making, and a model built fresh having no
/// memory of the last one is the wanted behaviour rather than a gap.
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
