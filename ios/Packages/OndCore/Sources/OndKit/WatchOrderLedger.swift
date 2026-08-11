import Foundation

/// What stops a session order running twice, or late.
///
/// The order travels in `applicationContext`, which is last-value-wins state
/// the system replays on every activation — so for as long as an order is the
/// last thing the phone said, every launch of the watch app receives it again.
/// The ledger is what turns that replayed state back into the event it means:
/// each order id is admitted at most once, and only while `issuedAt` is inside
/// the freshness window, so a context nobody delivered for an afternoon cannot
/// buzz a wrist at midnight.
///
/// On disk rather than in memory because the replay outlives the process: the
/// context that launched this run is redelivered to the next one, and a ledger
/// that forgot at exit would run the same order once per launch.
@MainActor
public final class WatchOrderLedger {
    /// How long an order stays runnable after the phone issues it.
    ///
    /// Long enough to ride out a launch, an authorization sheet and a slow
    /// pairing; short enough that an order delivered late is refused rather
    /// than starting a session nobody is waiting for. Ten minutes.
    public static let freshness: TimeInterval = 600

    /// How many executed ids the ledger keeps. One would be correct — only the
    /// newest order survives in the context — but the margin costs nothing and
    /// absorbs any future where more than one context shape is in flight.
    private static let capacity = 16

    /// `DefaultsJSONStore` rather than raw `UserDefaults` calls, so the decode
    /// failure semantics are the ones every other defaults-backed record in the
    /// app inherits. `SyncLedger` is the near neighbour and the wrong fit: it
    /// sorts its set, and this ledger's whole prune rule is "the newest few".
    private let executed: DefaultsJSONStore<[String]>

    public init(defaults: UserDefaults) {
        executed = DefaultsJSONStore(
            key: "watch.executedOrders",
            what: "the executed session orders",
            category: "watch-link",
            defaults: defaults
        )
    }

    /// Admits `order` exactly once, while it is fresh — recording it as
    /// executed in the same breath, so the caller that was told yes is the one
    /// obliged to act on it.
    ///
    /// Recorded at admission rather than when the session starts: between the
    /// two, the failure of a crashed launch costs one missed session, where a
    /// ledger that waited would let every later activation re-run an order
    /// whose moment has passed.
    ///
    /// - Parameter now: the wrist's wall clock. Measured against `issuedAt` by
    ///   distance rather than direction, because the two devices keep separate
    ///   clocks and the phone's may run ahead — an order from an apparently
    ///   near future is skew, not staleness.
    public func admit(_ order: WatchSessionOrder, at now: Date = .now) -> Bool {
        guard abs(now.timeIntervalSince(order.issuedAt)) < Self.freshness else { return false }

        var ids = executed.load() ?? []
        guard !ids.contains(order.id.uuidString) else { return false }

        ids.append(order.id.uuidString)
        executed.save(Array(ids.suffix(Self.capacity)))
        return true
    }
}
