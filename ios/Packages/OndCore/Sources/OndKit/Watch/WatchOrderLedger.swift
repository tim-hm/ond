import Foundation

/// What stops a session order running twice, or late. The order travels in
/// `applicationContext`, which the system replays on every activation, so
/// every launch receives it again; the ledger turns that state back into the
/// event it means — each id admitted at most once, and only inside the
/// freshness window. On disk because the replay outlives the process.
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

    /// Admits `order` exactly once, while it is fresh, recording it as
    /// executed in the same breath: a crashed launch then costs one missed
    /// session, where recording at session start would let every later
    /// activation re-run it. `issuedAt` is compared to `now` by distance, not
    /// direction — the phone's clock may run ahead, and near future is skew.
    public func admit(_ order: WatchSessionOrder, at now: Date = .now) -> Bool {
        guard abs(now.timeIntervalSince(order.issuedAt)) < Self.freshness else { return false }

        var ids = executed.load() ?? []
        guard !ids.contains(order.id.uuidString) else { return false }

        ids.append(order.id.uuidString)
        executed.save(Array(ids.suffix(Self.capacity)))
        return true
    }
}
