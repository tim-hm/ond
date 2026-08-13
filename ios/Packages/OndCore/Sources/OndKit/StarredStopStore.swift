import Foundation
import Observation

/// Which stops this person has starred, so Home keeps them in front of them.
///
/// The one thing on Home somebody *curates*. Everything else there is derived —
/// the totals, the streak, the hour's suggestion, the last thing breathed — and
/// all of it precisely so no store was needed. A star is the case derivation
/// cannot cover: "I want this one to hand whatever the clock thinks", which
/// nothing about a person's history says.
///
/// Keyed by `DialStop.id` — band and slug — rather than by technique slug, because
/// a stop is what gets starred and the same exercise is a different stop in two
/// bands: the protocol "Winding down" and the plain exercise it prescribes carry
/// different words, a different length and a different reason for being there. A
/// star on a stop the routes no longer send is silently inert, which is the right
/// answer for a key naming something that no longer exists.
///
/// A star set from an exercise's own screen names that exercise standing for itself
/// — `DialStop.id(of:)` — and never the protocol that happens to prescribe it. That
/// is what puts a row on Home the routing layer would not have offered at all, and
/// it is the only thing holding a catalogue entry there: unstar it and the row goes.
///
/// A set, not an order. Where a starred row sits is `HomeShelf`'s to decide, and it
/// decides by dial order — so two stars stay in the order Home would have shown
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
            what: "the starred stops",
            category: "home",
            defaults: defaults
        )
        starred = Set(store.load() ?? [])
    }

    /// Stars a stop, whether or not it already was.
    ///
    /// Separate from `toggle` because its one caller is not a person pressing a star:
    /// the composer stars an exercise the moment somebody writes one, so that the thing
    /// they just made is on Home rather than only in the Exercises list. A
    /// toggle there would un-star an exercise on the second save of the same slug —
    /// which is what editing one is.
    ///
    /// The detail screen's toolbar star is the second caller, and for a related
    /// reason: it stars one id and unstars a set, so a `toggle` there would be
    /// asking the wrong question of the wrong number of stops.
    public func star(_ id: String) {
        guard starred.insert(id).inserted else { return }
        store.save(starred.sorted())
    }

    /// Unstars every one of these, in a single write.
    ///
    /// A set rather than an id, because one exercise can be starred as more than one
    /// stop — `DialStop.ids(standingFor:)` — and a control that says "this exercise
    /// is on my Home screen" has to be able to take that back in one press. Pressing it
    /// three times to clear three bands would be the control lying about what it
    /// meant the first time.
    public func unstar(_ ids: Set<String>) {
        guard !starred.isDisjoint(with: ids) else { return }
        starred.subtract(ids)
        store.save(starred.sorted())
    }

    /// Whether this stop reads as starred, by any id that stands for it.
    ///
    /// Not `starred.contains(stop.id)`, which is the defect `DialStop.ids(standingFor:)`
    /// was written to name: Start here holds four of the catalogue's eleven, so
    /// somebody who starred Box Breathing from its own screen starred
    /// `everything/box-breathing`, and a row for the rung comparing only
    /// `startHere/box-breathing` draws an empty star over an exercise already
    /// pinned — then shelves a second identical row when it is pressed.
    ///
    /// A protocol is the deliberate exception. Its id names the *moment*, and
    /// "Winding down" is a different promise from the exercise it prescribes, so
    /// starring one is not starring the other.
    public func isStarred(_ stop: DialStop) -> Bool {
        stop.occasionSlug == nil
            ? !starred.isDisjoint(with: DialStop.ids(standingFor: stop.technique))
            : starred.contains(stop.id)
    }

    /// Stars a stop, or takes back every id standing for it.
    ///
    /// The asymmetry is `TechniqueStarButton`'s, and for its reason: starring
    /// writes the one id this stop carries in its own right, while unstarring
    /// has to be able to undo a star set on another screen under another band's
    /// key. Pressing a filled star three times to clear three bands would be the
    /// control lying about what it meant the first time.
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
