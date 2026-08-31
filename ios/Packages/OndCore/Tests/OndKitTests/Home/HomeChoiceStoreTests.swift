import Foundation
@testable import OndKit
import Testing

/// Home's default exercise and length: it survives a relaunch, and it does not
/// survive a deletion.
@MainActor
@Suite("Home's choice")
struct HomeChoiceStoreTests {
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "home-choice.\(UUID().uuidString)")
        return defaults ?? .standard
    }

    @Test("A fresh install has chosen nothing")
    func aFreshInstallHasNoChoice() {
        #expect(HomeChoiceStore(defaults: defaults()).choice == nil)
    }

    @Test("Choosing an exercise keeps the default length until a length is chosen")
    func choosingAnExerciseTakesTheDefaultLength() {
        let store = HomeChoiceStore(defaults: defaults())

        store.choose(slug: "box-breathing")
        #expect(store.choice == HomeChoice(
            slug: "box-breathing",
            minutes: HomeOffer.defaultMinutes
        ))

        store.choose(minutes: 10, for: "box-breathing")
        store.choose(slug: "coherent-breathing")
        #expect(store.choice == HomeChoice(slug: "coherent-breathing", minutes: 10))
    }

    @Test("The choice survives a relaunch")
    func theChoiceSurvivesARelaunch() {
        let defaults = defaults()
        HomeChoiceStore(defaults: defaults).choose(minutes: 3, for: "physiological-sigh")

        #expect(HomeChoiceStore(defaults: defaults).choice ==
            HomeChoice(slug: "physiological-sigh", minutes: 3))
    }

    @Test("Erasing forgets the choice in memory and on disk")
    func erasingForgetsBothHalves() async {
        let defaults = defaults()
        let store = HomeChoiceStore(defaults: defaults)
        store.choose(slug: "box-breathing")

        await store.erase()

        #expect(store.choice == nil)
        #expect(HomeChoiceStore(defaults: defaults).choice == nil)
    }
}
