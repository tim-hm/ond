import Foundation
import Observation

/// Which of home's cards this person has starred, so they lead whatever else the
/// hour suggests.
///
/// The first thing on this screen somebody *curates*. Everything else home orders
/// itself from — the routing layer's choice, the last session, what has been
/// breathed most — and `HomeDeck` derives all of it precisely so no store was
/// needed. A star is the case that derivation cannot cover: "I want this one in
/// front whatever the clock thinks", which nothing about a person's history says.
///
/// Keyed by `DialStop.id` — band and slug — rather than by technique slug, because
/// a card is what gets starred and the same exercise is a different card in two
/// bands: the moment "Winding down" and the plain exercise it prescribes carry
/// different words, a different length and a different reason for being there. A
/// star on a stop the routes no longer send is silently inert, which is the right
/// answer for a key naming something that no longer exists.
///
/// A star set from an exercise's own screen names that exercise standing for itself
/// — `DialStop.id(of:)` — and never the occasion that happens to prescribe it, which
/// is what puts a card on the board that the routing layer would not have dealt at
/// all. Unstarring that one takes the card off, where unstarring a routed card only
/// puts it back in its own order: a star is the only thing holding a catalogue entry
/// on home.
///
/// A set, not an order. Where a starred card sits is `HomeDeck`'s to decide, and it
/// decides by dial order — so two stars stay in the order home would have shown
/// them anyway, and starring cannot quietly become a second sort nobody asked for.
///
/// `UserDefaults` because it belongs to the install, on the same terms as the other
/// records here: a few dozen bytes, read at launch, written on a tap.
@MainActor
@Observable
public final class StarredStopStore: PersonalStore {
    /// The starred stops' ids.
    public private(set) var starred: Set<String>

    private let store: DefaultsJSONStore<[String]>

    public init(defaults: UserDefaults = .standard) {
        store = DefaultsJSONStore(
            key: "home.starred",
            what: "the starred cards",
            category: "home",
            defaults: defaults
        )
        starred = Set(store.load() ?? [])
    }

    /// Stars a card, whether or not it already was.
    ///
    /// Separate from `toggle` because its one caller is not a person pressing a star:
    /// the composer stars an exercise the moment somebody writes one, so that the thing
    /// they just made is in front of them rather than at the back of the board. A
    /// toggle there would un-star an exercise on the second save of the same slug —
    /// which is what editing one is.
    ///
    /// The detail screen's toolbar star is the second caller, and for a related
    /// reason: it stars one id and unstars a set, so a `toggle` there would be
    /// asking the wrong question of the wrong number of cards.
    public func star(_ id: String) {
        guard starred.insert(id).inserted else { return }
        store.save(starred.sorted())
    }

    /// Unstars every one of these, in a single write.
    ///
    /// A set rather than an id, because one exercise can be starred as more than one
    /// card — `DialStop.ids(standingFor:)` — and a control that says "this exercise
    /// is on my board" has to be able to take that back in one press. Pressing it
    /// three times to clear three bands would be the control lying about what it
    /// meant the first time.
    public func unstar(_ ids: Set<String>) {
        guard !starred.isDisjoint(with: ids) else { return }
        starred.subtract(ids)
        store.save(starred.sorted())
    }

    /// Stars an unstarred card, unstars a starred one.
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
