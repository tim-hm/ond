import Foundation
@testable import OndKit
import Testing

/// How the voices are offered, as opposed to what they say. The roster is data —
/// eight readers today, read from `voices.json` — so the picker's order and labels
/// are derived rather than written, and a manifest edit is the only thing that
/// moves them. These pin the derivation, because the failure it invites is not a
/// crash: it is a list of first names in an order with no visible reason for it.
@Suite("How the voices are offered")
struct VoiceRosterTests {
    /// Every voice names the region it reads in, so the sort has something
    /// visible to sort by.
    @Test("A voice is offered by name and region")
    func aVoiceIsNamedWithItsRegion() {
        for voice in SessionVoice.all {
            let title = SessionSound.voice(voice).title
            #expect(title.hasPrefix(voice.title), "\(voice.slug) lost its name")
            #expect(title.hasSuffix(voice.region), "\(voice.slug) did not say where it reads")
            #expect(voice.region != voice.variant, "\(voice.variant) is not a region anyone knows")
        }
        #expect(SessionSound.tones.title == "Tones")
    }

    /// A manifest naming a region the system cannot place shows the tag rather
    /// than a name with nothing after the dash.
    @Test("An unplaceable variant falls back to its tag")
    func anUnknownVariantIsShownAsWritten() {
        let voice = SessionVoice(slug: "x", title: "X", variant: "zz-ZZ", isDefault: false)
        #expect(voice.region == "zz-ZZ")
    }

    /// Tones lead, and the voices follow grouped by region and named within it.
    ///
    /// Tones first because it is the one option that is not a person, and the
    /// one a session had before any of them existed.
    @Test("Tones lead, and the voices are grouped by region")
    func theRosterIsOrderedForReading() {
        #expect(SessionSound.allCases.first == .tones)

        let voices = SessionSound.allCases.compactMap(\.voice)
        #expect(voices.count == SessionVoice.all.count)

        let keys = voices.map { [$0.variant, $0.title] }
        #expect(keys == keys.sorted { $0.lexicographicallyPrecedes($1) }, "the roster reshuffled")
    }

    /// Two voices cannot share a slug: it is the folder the clips live in and
    /// the string the setting persists as, so a collision would silently hand
    /// one voice the other's audio.
    @Test("A slug names one voice")
    func slugsAreUnique() {
        let slugs = SessionVoice.all.map(\.slug)
        #expect(Set(slugs).count == slugs.count, "\(slugs) has a repeat")
    }

    /// A stored setting round-trips through its slug, including for a voice
    /// added after the setting was written — and a slug this build has no clips
    /// for reads as nothing rather than as a voice with no audio.
    @Test("A setting survives the roster changing under it")
    func aStoredVoiceRoundTrips() {
        for sound in SessionSound.allCases {
            #expect(SessionSound(rawValue: sound.rawValue) == sound)
        }
        #expect(SessionSound(rawValue: "a-voice-this-build-never-shipped") == nil)
    }
}
