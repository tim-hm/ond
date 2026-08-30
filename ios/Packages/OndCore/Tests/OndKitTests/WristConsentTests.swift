import Foundation
@testable import OndKit
import Testing

/// Whether the wrist has to ask before it runs anything. The watch target has
/// no tests, so this is the only place the rule is checked — and every failure
/// mode is silent from a screen: a wrist that asks twice merely annoys, and one
/// that never asks runs sessions nobody agreed to. `docs/product/watch-consent.md`
/// is the decision these pin.
@MainActor
@Suite("Consent on the wrist")
struct WristConsentTests {
    @Test("A wrist that has met no phone asks for itself")
    func asksWhenNothingIsKnown() {
        #expect(store().needsConsent(whenAnotherDeviceAgreedTo: nil))
    }

    /// The point of carrying the phone's agreement at all, and the record says
    /// what somebody read and when: writing one here would date words this
    /// person never saw on this device, and it would then outlive the deletion
    /// that took the phone's own record away.
    @Test("The phone's agreement spares the wrist its screen and writes nothing")
    func skipsWhatThePhoneHasAgreed() {
        let wrist = store()

        #expect(!wrist.needsConsent(whenAnotherDeviceAgreedTo: SafetyConsent.current.version))
        #expect(wrist.agreed == nil)
    }

    /// The reason a version travels rather than a flag. A hazard added to the
    /// copy has to reach a wrist whose phone agreed to the copy without it.
    @Test("An agreement to older terms does not cover newer ones")
    func asksWhenThePhonesAgreementIsStale() {
        #expect(store(version: 2).needsConsent(whenAnotherDeviceAgreedTo: 1))
    }

    @Test("Agreeing on the wrist closes the screen and is recorded")
    func agreeingRecordsIt() {
        let wrist = store()

        wrist.record()

        #expect(!wrist.needsConsent(whenAnotherDeviceAgreedTo: nil))
        #expect(wrist.agreed?.text == SafetyConsent.current.text)
    }

    /// The whole channel in one pass: the phone reads its own record, the
    /// number survives the dictionary that is its only form between the two
    /// devices, and the wrist stops asking. A break anywhere along it shows up
    /// as a screen somebody has already read once.
    @Test("The phone's agreement travels the pairing and closes the wrist's screen")
    func travelsTheWholePairing() async throws {
        let phone = inbox()
        var sent: WatchHandoff?

        await outbox(agreed: SafetyConsent.current.version).handOver { sent = $0 }
        let context = try #require(sent).dictionary
        try await phone.adopt(#require(WatchHandoff(dictionary: context)))

        #expect(!store().needsConsent(whenAnotherDeviceAgreedTo: phone.agreedConsentVersion))
    }

    /// Deleting the account leaves the phone with no version to send, and the
    /// wrist leaning on nothing. Absent means ask, which is what makes the
    /// deletion honest on both devices.
    @Test("A phone that no longer says it agreed puts the terms back")
    func asksAgainWhenThePhoneWithdraws() async {
        let phone = inbox()
        let id = UUID()

        await phone.adopt(WatchHandoff(userId: id, agreedConsentVersion: 1))
        await phone.adopt(WatchHandoff(userId: id))

        #expect(store().needsConsent(whenAnotherDeviceAgreedTo: phone.agreedConsentVersion))
    }

    /// An agreement made on the wrist is the wrist's own, and a phone that has
    /// never agreed does not take it back.
    @Test("A wrist that agreed for itself does not ask because the phone has not")
    func keepsItsOwnAgreement() {
        let wrist = store()

        wrist.record()

        #expect(!wrist.needsConsent(whenAnotherDeviceAgreedTo: nil))
    }

    /// A wrist nobody has agreed on, over a suite of its own.
    private func store(version: Int = SafetyConsent.current.version) -> SafetyConsentStore {
        SafetyConsentStore(terms: terms(version: version), defaults: scratchDefaults())
    }

    /// The phone's half of the pairing, saying it agreed to `agreed` and
    /// nothing else about the person.
    private func outbox(agreed: Int?) -> WatchHandoffOutbox {
        WatchHandoffOutbox(
            identity: StubIdentity(id: UUID()),
            scores: StubScores(),
            defaults: scratchDefaults(),
            agreedConsentVersion: { agreed }
        )
    }

    /// The wrist's half, over throwaway storage so one test's mirrored
    /// agreement cannot be read by the next or by the developer's own watch.
    private func inbox() -> WatchHandoffInbox {
        WatchHandoffInbox(
            identity: ProvisionedUserIdentityStore(storage: FakeStorage()),
            stores: [],
            orders: WatchOrderLedger(defaults: scratchDefaults()),
            defaults: scratchDefaults()
        )
    }

    /// The shipping words at a version a test chooses, so raising the terms
    /// here does not mean editing the copy every screen shows.
    private func terms(version: Int) -> SafetyConsent {
        let current = SafetyConsent.current
        return SafetyConsent(
            version: version,
            title: current.title,
            intro: current.intro,
            points: current.points,
            agreement: current.agreement
        )
    }
}
