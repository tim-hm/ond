import Foundation
import Observation

/// Which stops this person has starred, so they stay near the top of Home's
/// sheet and the lists that draw the star. Keyed by `DialStop.id` — band and
/// slug, not technique slug: the same exercise is a different stop in two
/// bands, and a star on a stop the routes no longer send is silently inert.
/// A set, not an order: where a starred row sits is `HomeOffer`'s to decide.
@MainActor
@Observable
public final class StarredStopStore: PersonalStore {
    /// The starred stops' ids.
    public private(set) var starred: Set<String>

    private let store: DefaultsJSONStore<[String]>

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsJSONStore(
            key: "home.starred",
            what: "the starred stops",
            category: "home",
            defaults: defaults
        )
        starred = Set(store.load() ?? [])
    }

    /// Stars a stop, whether or not it already was. Separate from `toggle`:
    /// the composer stars an exercise the moment somebody writes one, and a
    /// toggle there would un-star it on the second save of the same slug. The
    /// detail screen's toolbar star also needs it — it stars one id and
    /// unstars a set.
    public func star(_ id: String) {
        guard starred.insert(id).inserted else { return }
        store.save(starred.sorted())
    }

    /// Unstars every one of these, in a single write. A set rather than an
    /// id: one exercise can be starred as more than one stop —
    /// `DialStop.ids(standingFor:)` — and "this exercise is on my Home
    /// screen" must be revocable in one press, not one per band.
    public func unstar(_ ids: Set<String>) {
        guard !starred.isDisjoint(with: ids) else { return }
        starred.subtract(ids)
        store.save(starred.sorted())
    }

    /// Whether this stop reads as starred, by any id that stands for it. Not
    /// `starred.contains(stop.id)`: the same exercise can be persisted under
    /// its standalone id or a retained band id, and a row comparing only its
    /// own id would draw an empty star over an exercise already pinned. A
    /// moment is the exception — its id names the moment, not the exercise.
    public func isStarred(_ stop: DialStop) -> Bool {
        stop.occasionSlug == nil
            ? DialStop.isStarred(stop.technique, among: starred)
            : starred.contains(stop.id)
    }

    /// Stars a stop, or takes back every id standing for it. Asymmetric
    /// because starring writes the one id this stop carries in its own right,
    /// while unstarring must undo a star set on another screen under another
    /// band's key — one press, not one per band.
    public func toggle(_ stop: DialStop) {
        guard stop.occasionSlug == nil else {
            toggle(stop.id)
            return
        }

        if isStarred(stop) {
            unstar(DialStop.ids(standingFor: stop.technique))
        } else {
            star(stop.id)
        }
    }

    /// Stars an unstarred stop, unstars a starred one.
    ///
    /// Sorted on the way to disk. The set has no order and JSON does, so writing it
    /// raw would rewrite the key with the same stars in a different sequence on
    /// every tap — noise in a payload somebody may one day have to read.
    public func toggle(_ id: String) {
        if starred.contains(id) {
            starred.remove(id)
        } else {
            starred.insert(id)
        }
        store.save(starred.sorted())
    }

    /// Forgets every star. What somebody chose to keep in front of them is as
    /// personal as what they breathed, and a deletion that left it would leave the
    /// next person on this device someone else's shortlist.
    public func erase() async {
        starred = []
        store.erase()
    }
}
