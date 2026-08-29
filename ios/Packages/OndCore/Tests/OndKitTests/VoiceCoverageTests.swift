import Foundation
@testable import OndKit
import Testing

/// What holds the rendered audio to the words the app thinks it is saying.
/// `generate:voice` sits outside the `generate` chain — it spends a paid API key
/// and a macOS-only encoder — so forgetting it is the likely mistake, and a
/// forgotten render is invisible: clips still play, sound right, and say what the
/// app stopped saying. These notice, needing no key, no network, no simulator.
@Suite("What the app says out loud")
struct VoiceCoverageTests {
    /// Every breath, in every voice, in every register, has something to say. The
    /// cross product rather than a list: a register is a second dimension, and
    /// the failure it invites is silent — a register added without clips reads
    /// correctly on screen and says the plain thing out loud. A fifth `Passage`
    /// or a third `CopyRegister` lands here as a failure, not an unnoticed gap.
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
    /// `TechniqueWords.swift`, does not re-render, and the app ships audio saying
    /// the old sentence with nothing anywhere to say so. Held to `spoken(in:)`
    /// rather than to `instruction`, which is the printed form and says "through
    /// your mouth" where the spoken one does not.
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
    /// produce one. The ceiling is alternate-nostril's authored four seconds, the
    /// longest phase that ever takes a passage cue — a clip past it could not be
    /// spoken anywhere, which is the render having drifted.
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

/// Where a practice changes shape, and what marks it.
///
/// Pinned against the seeded catalogue rather than a fixture, because "which
/// exercises have more than one stage" is a fact about the seed and the bell
/// exists for exactly those.
@Suite("The seam between stages")
struct StageSeamTests {
    /// A stage turns over once however many cycles it holds. Wim Hof's first
    /// stage is thirty breaths, and a bell on each of them would be the
    /// opposite of the point.
    @Test("A stage opens once, whatever it is made of")
    func aStageOpensOnce() {
        let technique = SeededCatalogue.technique("wim-hof-rounds")
        let timeline = SessionTimeline(technique: technique)

        // Every stage of every round, less the one the session opens on. A
        // round boundary is a turnover too — round two starts the thirty
        // breaths again, and that seam is as worth marking as the others.
        let openers = timeline.beats.filter(\.opensStage)
        let seams = timeline.rounds * technique.stages.count - 1
        #expect(openers.count == seams, "\(timeline.rounds) rounds of \(technique.stages.count)")
        #expect(Set(openers.map(\.stage)) == Set(0 ..< technique.stages.count))

        // Every opener is the top of its stage, not somewhere inside it.
        for beat in openers {
            #expect(beat.cycle == 0, "stage \(beat.stage) opened mid-cycle")
            #expect(beat.phase == 0, "stage \(beat.stage) opened mid-breath")
        }
    }

    /// A round boundary is a stage boundary too, and the larger of the two. Wim
    /// Hof is three rounds of four stages: eleven seams, of which two are rounds
    /// turning over. Pinned because the two bells differ, and the rule that
    /// separates them — a stage opening on stage zero — reads as an
    /// implementation detail until it is stated as a count.
    @Test("A round turning over is marked apart from a stage")
    func aRoundIsTheLargerSeam() {
        let technique = SeededCatalogue.technique("wim-hof-rounds")
        let timeline = SessionTimeline(technique: technique)

        let rounds = timeline.beats.filter(\.opensRound)
        #expect(rounds.count == timeline.rounds - 1, "one per round after the first")
        for beat in rounds {
            #expect(beat.stage == 0, "a round opened on stage \(beat.stage)")
            #expect(beat.opensStage, "a round turning over is a stage turning over")
        }

        // The rest are stages within a round, and outnumber them.
        let withinARound = timeline.beats.filter { $0.opensStage && !$0.opensRound }
        #expect(withinARound.count == timeline.rounds * (technique.stages.count - 1))
        for beat in withinARound {
            #expect(beat.stage != 0, "a stage seam sat where a round seam belongs")
        }
    }

    /// A sigh is one sentence even though phase boundaries divide it into three
    /// clips. Both doses take the same stems; only their timings differ.
    @Test("Both sighs speak one connected instruction")
    func sighsUseConnectedClips() {
        for slug in ["physiological-sigh", "cyclic-sighing"] {
            let beats = Array(SessionTimeline(technique: SeededCatalogue.technique(slug))
                .beats.prefix(3))

            #expect(beats.map(\.instruction) == ["Breathe in", "And in", "And breathe out"])
            #expect(beats.map(\.spokenInstruction) == [
                "Breathe in", "And in", "And breathe out",
            ])
            #expect(beats.map(\.clipStem) == ["sigh-in", "sigh-and-in", "sigh-and-out"])
            #expect(beats.map(\.stacksOnPrevious) == [false, true, false])
        }

        for voice in SessionVoice.all {
            let lines = VoiceClips.lines(for: voice)
            #expect(lines["sigh-in"]?.text == "Breathe in")
            #expect(lines["sigh-and-in"]?.text == "And in")
            #expect(lines["sigh-and-out"]?.text == "And breathe out")
            #expect(lines["short-more"] == nil)
        }
    }

    /// A breath that reverses the one before it stacks on nothing. Bellows
    /// breath alternates all the way through, so it is the counter-case.
    @Test("Alternating breaths never stack")
    func alternatingBreathsNeverStack() {
        for slug in ["bellows-breath", "box-breathing", "coherent-breathing"] {
            let beats = SessionTimeline(technique: SeededCatalogue.technique(slug)).beats
            let stacked = beats.filter(\.stacksOnPrevious)
            #expect(stacked.isEmpty, "\(slug) stacked \(stacked.count) breaths")
        }
    }

    /// The session starting is not a stage changing — the countdown has already
    /// said so, and a bell on the first breath would ring over it.
    @Test("The first breath of a session opens nothing")
    func theFirstBeatIsSilent() {
        for technique in SeededCatalogue.techniques {
            let timeline = SessionTimeline(technique: technique)
            #expect(timeline.beats.first?.opensStage == false, "\(technique.slug) rang at the off")
        }
    }

    /// A single-stage exercise has no seam, so it never rings.
    @Test("A practice of one stage has nothing to mark")
    func oneStageNeverRings() {
        for technique in SeededCatalogue.techniques where technique.stages.count == 1 {
            let rings = SessionTimeline(technique: technique).beats.filter(\.opensStage)
            #expect(rings.isEmpty, "\(technique.slug) rang with nothing to mark")
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
    /// The exercise the passage cue exists for: alternate-nostril is the one place
    /// which nostril is the whole instruction, so the short form loses the exercise.
    /// As authored, not at the dialled floor: at the retuned pace the sentence runs
    /// about three seconds and the floor *is* three, so the fastest dial gets the
    /// word — the fallback working. What must not happen is unspoken out of the box.
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
    /// fitted: Wim Hof runs 1.5s each way and "Breathe in" is under a second, so
    /// arithmetic alone hands it the sentence — which then runs two-thirds of the
    /// breath it describes. The one place the fit rule asks more than "does it
    /// fit", so it is pinned against the exercises it was decided on.
    @Test("A breath of two seconds or less is cued in one word")
    func theQuickBreathsAreCuedInOneWord() {
        for slug in ["wim-hof-rounds", "bellows-breath"] {
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

    /// The other end. A dial can take a phase below the room its preferred line
    /// needs, including the sigh's half-second top-up. Such a phase keeps its
    /// tone rather than clipping a word at the next boundary.
    @Test("A phase at its floor is never given a clip that overruns it")
    func aFastPhaseIsNeverOverrun() {
        for technique in SeededCatalogue.techniques {
            for beat in flooredTimeline(for: technique).beats {
                guard let stem = beat.clipStem else { continue }
                let spoken = VoiceClips.longest(stem) ?? .infinity

                #expect(
                    spoken <= beat.duration.seconds,
                    "\(technique.slug)'s \(stem) needs \(spoken)s in \(beat.duration.seconds)s"
                )
            }
        }
    }

    /// The guarantee the slowest-voice rule buys, stated where the next voice added
    /// will trip over it: whichever cue a phase is given, *every* voice can say it
    /// inside the phase. A voice added without calibrating its speed reads slower than
    /// the ones this was measured against — Faye did, until she was given her own pace
    /// — and this is what says so rather than a session cut off mid-word.
    @Test("No voice overruns the phase it is speaking into")
    func noVoiceOverrunsItsPhase() {
        for voice in SessionVoice.all {
            let lines = VoiceClips.lines(for: voice)

            for technique in SeededCatalogue.techniques {
                for beat in flooredTimeline(for: technique).beats {
                    let spoken = beat.clipStem.flatMap { lines[$0]?.seconds }

                    #expect(
                        (spoken ?? 0) <= beat.duration.seconds,
                        """
                        \(voice.slug) needs \(spoken ?? 0)s for \
                        \(technique.slug)'s \(beat.instruction), \
                        which runs \(beat.duration.seconds)s
                        """
                    )
                }
            }
        }
    }

    private func flooredTimeline(for technique: Technique) -> SessionTimeline {
        let stages = technique.stages.map { stage in
            Stage(
                phases: stage.phases.map { $0.dialled(to: $0.range.lowerBound) },
                cycles: stage.cycles,
                openEnded: stage.openEnded
            )
        }
        return SessionTimeline(stages: stages, rounds: technique.recommendedRounds)
    }
}
