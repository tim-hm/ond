import Foundation
@testable import OndKit
import Testing

/// What holds the rendered audio to the words the app thinks it is saying.
///
/// `mise run generate:voice` is deliberately outside the `generate` chain — it
/// spends a paid API key and a macOS-only encoder, which a headless environment
/// has neither of. That makes forgetting to run it the likely mistake rather
/// than the unlikely one, and a forgotten render is invisible: the clips still
/// play, still sound right, and say something the app stopped saying. These
/// tests are the thing that notices, and they need no key, no network and no
/// simulator to do it.
@Suite("What the app says out loud")
struct VoiceCoverageTests {
    /// Every breath, in every voice, has something to say. A fifth `Passage`
    /// arrives as a compile error in `Breath.instruction` and as this failing.
    @Test("Every voice has a clip for every breath")
    func everyBreathIsSpoken() {
        // The voices are read from the render rather than declared, so an
        // unreadable manifest is an empty list — which every loop in this file
        // would pass without executing once. Asserted here so that failure has
        // somewhere to land.
        #expect(!SessionVoice.all.isEmpty, "voices.json shipped no voices at all")

        for voice in SessionVoice.all {
            let lines = VoiceClips.lines(for: voice)
            #expect(!lines.isEmpty, "\(voice.slug) shipped no clips at all")

            for breath in Breath.allCases {
                #expect(lines[breath.clipName] != nil, "\(voice.slug) cannot say \(breath)")
                #expect(
                    lines[breath.shortClipName] != nil,
                    "\(voice.slug) has no short form for \(breath)"
                )
            }
        }
    }

    /// The failure this whole arrangement exists for: somebody retunes a cue in
    /// `TechniqueWords.swift`, does not re-render, and the app ships audio
    /// saying the old sentence with nothing anywhere to say so.
    @Test("Every clip says what the app says it says")
    func theAudioMatchesTheWords() {
        for voice in SessionVoice.all {
            let lines = VoiceClips.lines(for: voice)

            for breath in Breath.allCases {
                #expect(
                    lines[breath.clipName]?.text == breath.instruction,
                    """
                    \(voice.slug)/\(breath.clipName) says \
                    \(lines[breath.clipName]?.text ?? "nothing") \
                    where the app says \(breath.instruction)
                    """
                )
            }

            for kind in [PhaseKind.inhale, .exhale] {
                let breath = Breath(kind: kind, through: Passage.nose)
                #expect(lines[breath.shortClipName]?.text == kind.shortInstruction)
            }
        }
    }

    /// A clip is bounded at both ends. Nothing under a fifth of a second is a
    /// word, and the render's trimming is what would fail quietly enough to
    /// produce one.
    ///
    /// The ceiling is alternate-nostril breathing's authored four seconds,
    /// which is the longest phase that ever takes a passage cue — the holds run
    /// longer but say one word. A clip past it could not be spoken anywhere,
    /// which is the render having drifted rather than a pace somebody chose.
    @Test("No clip is too short to be a word or too long for a phase")
    func clipsAreOfAPlausibleLength() {
        for voice in SessionVoice.all {
            for (key, line) in VoiceClips.lines(for: voice) {
                #expect(line.seconds > 0.2, "\(voice.slug)/\(key) is \(line.seconds)s")
                #expect(line.seconds < 4.0, "\(voice.slug)/\(key) is \(line.seconds)s")
            }
        }
    }
}

/// Whether the seeded exercises can actually be spoken at the pace they run.
///
/// The reason the two-tier fallback exists, pinned against the real catalogue
/// rather than against numbers copied out of it — a reseeded duration should
/// move these, and a reseed that makes an exercise unspeakable should say so.
@Suite("What a session finds room to say")
struct SpokenCueFitTests {
    /// The exercise the passage cue exists for. Alternate-nostril breathing is
    /// the one technique where which nostril is the whole instruction, so it is
    /// the one place the short form loses the exercise rather than trimming it.
    ///
    /// As authored, not at the dialled floor. It held at the floor while the
    /// voices spoke "Breathe in" in a second; at the slower pace they were
    /// retuned to, the sentence runs to around three and the floor *is* three.
    /// Somebody who dials alternate-nostril down to its fastest has asked for a
    /// pace the sentence does not fit, and gets the word — which is the fallback
    /// working, not failing. What must not happen is the exercise arriving
    /// unspoken out of the box.
    @Test("Alternating nostrils names the nostril as authored")
    func theNostrilIsNamedAsAuthored() {
        let technique = SeededCatalogue.technique("alternate-nostril")

        for phase in technique.stages.flatMap(\.phases) where phase.breath.passage?.side != nil {
            #expect(
                phase.breath.spokenCue(within: phase.duration) == .full,
                "no room for \(phase.breath.instruction) in \(phase.duration)"
            )
        }
    }

    /// The other end. Bellows breath runs a second each way and physiological
    /// sigh's top-up is shorter still, and a cue that overran them would be
    /// naming a breath already finished.
    @Test("A phase too brief for the sentence is never given the sentence")
    func aFastPhaseIsNeverOverrun() {
        for technique in SeededCatalogue.techniques {
            for phase in technique.stages.flatMap(\.phases) {
                let floor = phase.range.lowerBound
                let room = floor.seconds
                let full = VoiceClips.longest(phase.breath.clipName) ?? .infinity
                let short = VoiceClips.longest(phase.breath.shortClipName) ?? .infinity
                let where_ = "\(technique.slug)'s \(phase.breath.instruction) in \(room)s"

                switch phase.breath.spokenCue(within: floor) {
                case .full:
                    #expect(full <= room, "sentence does not fit \(where_)")
                case .short:
                    #expect(short <= room, "word does not fit \(where_)")
                    #expect(full > room, "the sentence would have fitted \(where_)")
                case .tone:
                    #expect(short > room, "the word would have fitted \(where_)")
                }
            }
        }
    }

    /// The guarantee the slowest-voice rule buys, stated where the next voice
    /// added will trip over it: whichever cue a phase is given, *every* voice
    /// can say it inside the phase. A voice added without calibrating its speed
    /// reads slower than the ones this was measured against — Faye did, until
    /// she was given her own pace — and this is what says so rather than a
    /// session cut off mid-word.
    @Test("No voice overruns the phase it is speaking into")
    func noVoiceOverrunsItsPhase() {
        for voice in SessionVoice.all {
            let lines = VoiceClips.lines(for: voice)

            for technique in SeededCatalogue.techniques {
                for phase in technique.stages.flatMap(\.phases) {
                    let floor = phase.range.lowerBound
                    let room = floor.seconds

                    let spoken: Double? = switch phase.breath.spokenCue(within: floor) {
                    case .full: lines[phase.breath.clipName]?.seconds
                    case .short: lines[phase.breath.shortClipName]?.seconds
                    case .tone: nil
                    }

                    #expect(
                        (spoken ?? 0) <= room,
                        """
                        \(voice.slug) needs \(spoken ?? 0)s for \
                        \(technique.slug)'s \(phase.breath.instruction), \
                        which runs \(room)s
                        """
                    )
                }
            }
        }
    }
}
