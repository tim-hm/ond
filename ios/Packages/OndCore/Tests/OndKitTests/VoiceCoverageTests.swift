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
    /// Every breath, in every voice, in every register, has something to say.
    ///
    /// The cross product rather than a list, because a register is a second
    /// dimension of the vocabulary and the failure it invites is a silent one:
    /// a register added without clips reads correctly on screen and says the
    /// plain thing out loud. A fifth `Passage` or a third `CopyRegister` lands
    /// here as a failure rather than as a gap nobody looks for.
    @Test("Every voice has a clip for every breath, in every register")
    func everyBreathIsSpoken() {
        // The voices are read from the render rather than declared, so an
        // unreadable manifest is an empty list — which every loop in this file
        // would pass without executing once. Asserted here so that failure has
        // somewhere to land.
        #expect(!SessionVoice.all.isEmpty, "voices.json shipped no voices at all")

        for voice in SessionVoice.all {
            let lines = VoiceClips.lines(for: voice)
            #expect(!lines.isEmpty, "\(voice.slug) shipped no clips at all")

            for register in CopyRegister.allCases {
                for breath in Breath.allCases {
                    #expect(
                        lines[breath.clipName(in: register)] != nil,
                        "\(voice.slug) cannot say \(breath) in \(register)"
                    )
                    #expect(
                        lines[breath.shortClipName] != nil,
                        "\(voice.slug) has no short form for \(breath)"
                    )
                }
            }
        }
    }

    /// The failure this whole arrangement exists for: somebody retunes a cue in
    /// `TechniqueWords.swift`, does not re-render, and the app ships audio
    /// saying the old sentence with nothing anywhere to say so.
    ///
    /// Held to `spoken(in:)` rather than to `instruction`, which is the printed
    /// form and says "through your mouth" where the spoken one does not.
    @Test("Every clip says what the app says it says")
    func theAudioMatchesTheWords() {
        for voice in SessionVoice.all {
            let lines = VoiceClips.lines(for: voice)

            for register in CopyRegister.allCases {
                for breath in Breath.allCases {
                    let stem = breath.clipName(in: register)
                    #expect(
                        lines[stem]?.text == breath.spoken(in: register),
                        """
                        \(voice.slug)/\(stem) says \
                        \(lines[stem]?.text ?? "nothing") \
                        where the app says \(breath.spoken(in: register))
                        """
                    )
                }
            }

            for kind in [PhaseKind.inhale, .exhale] {
                let breath = Breath(kind: kind, through: Passage.nose)
                #expect(lines[breath.shortClipName]?.text == kind.shortInstruction)
            }
        }
    }

    /// A mouth breath takes the plain clip, and takes it in both registers.
    ///
    /// The one place the spoken and printed forms diverge on purpose, so it is
    /// asserted rather than left to the cross product above — which would still
    /// pass if `spokenAs` and `spoken` drifted together in the same direction.
    @Test("The mouth is printed but never spoken")
    func theMouthGoesUnsaid() {
        for register in CopyRegister.allCases {
            #expect(Breath.inhale(through: .mouth).clipName(in: register) == "inhale")
            #expect(Breath.exhale(through: .mouth).clipName(in: register) == "exhale")
            #expect(Breath.inhale(through: .mouth).spoken(in: register) == "Breathe in")
            #expect(Breath.exhale(through: .mouth).spoken(in: register) == "Breathe out")
        }
        #expect(Breath.exhale(through: .mouth).instruction == "Breathe out through your mouth")
    }

    /// The playful register speaks its own words where it has them, and the
    /// plain ones everywhere else — the same fallback the printed form makes,
    /// so a route never hears one register and reads another.
    @Test("The playful register is spoken where it is written")
    func thePlayfulRegisterIsSpoken() {
        #expect(Breath.inhale(through: .nose).clipName(in: .playful) == "inhale-playful")
        #expect(Breath.exhale(through: .nose).clipName(in: .playful) == "exhale-playful")
        #expect(Breath.inhale(through: .nose).spoken(in: .playful) == "Smell the flower")

        // No playful form, so it falls back rather than borrowing the nose's.
        #expect(Breath.exhale(through: .mouth).clipName(in: .playful) == "exhale")
        #expect(Breath.holdIn.clipName(in: .playful) == "hold")
        #expect(Breath.exhale(through: .leftNostril).clipName(in: .playful)
            == "exhale-left-nostril")
    }

    /// Exactly one voice is the default, and the app agrees with the manifest
    /// about which. A roster that lost its default would silently fall to
    /// whichever voice sorted first.
    @Test("One voice is the default, and it is the one the manifest marked")
    func oneVoiceIsPreferred() {
        #expect(SessionVoice.all.filter(\.isDefault).count == 1)
        #expect(SessionVoice.preferred?.slug == "faye")
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

    /// The quick exercises take the word, even where the sentence would have
    /// fitted.
    ///
    /// Wim Hof runs 1.5s each way and "Breathe in" is under a second, so
    /// arithmetic alone hands it the sentence — and it then runs two-thirds of
    /// the way through the breath it is describing. This is the one place the
    /// fit rule asks for more than "does it fit", so it is pinned against the
    /// exercises it was decided on rather than against the constant.
    @Test("A breath of two seconds or less is cued in one word")
    func theQuickBreathsAreCuedInOneWord() {
        for slug in ["wim-hof-rounds", "bellows-breath", "physiological-sigh"] {
            let technique = SeededCatalogue.technique(slug)

            let breaths = technique.stages.flatMap(\.phases)
                .filter { $0.breath.kind != .holdIn && $0.breath.kind != .holdOut }

            for phase in breaths where phase.duration.seconds <= VoiceClips.sentenceFloor {
                #expect(
                    phase.breath.spokenCue(within: phase.duration) == .short,
                    "\(slug)'s \(phase.duration) \(phase.breath) took more than a word"
                )
            }
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
                let full = VoiceClips.longest(phase.breath.clipName()) ?? .infinity
                let short = VoiceClips.longest(phase.breath.shortClipName) ?? .infinity
                let where_ = "\(technique.slug)'s \(phase.breath.instruction) in \(room)s"

                switch phase.breath.spokenCue(within: floor) {
                case .full:
                    #expect(full <= room, "sentence does not fit \(where_)")
                case .short:
                    #expect(short <= room, "word does not fit \(where_)")
                    #expect(
                        full > room || room <= VoiceClips.sentenceFloor,
                        "the sentence would have fitted, and there was room for it: \(where_)"
                    )
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
                    case .full: lines[phase.breath.clipName()]?.seconds
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
